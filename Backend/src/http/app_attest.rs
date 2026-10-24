//! `/api/v1/app-attest`: one-time challenges and key registration. Not part of the published API docs.

use axum::Json;
use axum::extract::State;
use axum::extract::rejection::BytesRejection;
use axum::http::{HeaderMap, StatusCode};
use bytes::Bytes;
use serde_json::{Value, json};

use super::validation::{self, Validator, has_length, is_base64};
use super::{ApiError, AppState, ClientIp};
use crate::app_attest::Attestation;
use crate::security::decode_base64_lenient;

pub async fn challenge(State(state): State<AppState>, ClientIp(ip): ClientIp) -> Result<Json<Value>, ApiError> {
    let challenge = state.app_attest.issue_challenge(&ip).await?;
    Ok(Json(json!({ "challenge": challenge })))
}

pub async fn attestations(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Result<StatusCode, ApiError> {
    let body = validation::body(body)?;
    let object = validation::json_object(&headers, &body)?;
    let mut validator = Validator::new(&object);
    let key_id = validator.string(
        "keyId",
        has_length(20, 255),
        "must be longer than or equal to 20 and shorter than or equal to 255 characters",
    );
    let challenge = validator.string(
        "challenge",
        has_length(20, 128),
        "must be longer than or equal to 20 and shorter than or equal to 128 characters",
    );
    let attestation = validator.string(
        "attestation",
        |value| is_base64(value) && value.len() <= 60_000,
        "must be base64 encoded and shorter than or equal to 60000 characters",
    );
    validator.finish()?;
    let (Some(key_id), Some(challenge), Some(attestation)) = (key_id, challenge, attestation) else {
        unreachable!("validated");
    };
    let attestation = decode_base64_lenient(attestation).unwrap_or_default();
    state.app_attest.register_attestation(&Attestation { key_id, challenge, attestation: &attestation }).await?;
    Ok(StatusCode::NO_CONTENT)
}
