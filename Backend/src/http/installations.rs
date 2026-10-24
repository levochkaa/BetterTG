//! `/api/v1/installations`: created with an `Idempotency-Key` and, when enforced, an App Attest assertion over the
//! exact body; managed afterwards with the bearer secret returned once at creation.

use axum::Json;
use axum::extract::rejection::BytesRejection;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use uuid::Uuid;

use super::validation::{self, Validator, is_apns_token};
use super::{ApiError, AppState};
use crate::app_attest::AppAttestError;
use crate::db::{ApnsEnvironment, Installation};
use crate::installations::{InstallationCreated, InstallationError, NewInstallationRequest, TelegramSubscription};

impl From<InstallationError> for ApiError {
    fn from(error: InstallationError) -> Self {
        match error {
            InstallationError::Conflict => {
                ApiError::new(StatusCode::CONFLICT, "installation creation is already running")
            }
            InstallationError::NotFound => ApiError::bare(StatusCode::NOT_FOUND),
            InstallationError::Unavailable(error) => ApiError::internal(error),
        }
    }
}

impl From<AppAttestError> for ApiError {
    fn from(error: AppAttestError) -> Self {
        match error {
            AppAttestError::Unauthorized(message) => ApiError::new(StatusCode::UNAUTHORIZED, message),
            AppAttestError::RateLimited => ApiError::rate_limited(),
            AppAttestError::Unavailable(error) => ApiError::internal(error),
        }
    }
}

fn header<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
    headers.get(name).and_then(|value| value.to_str().ok())
}

async fn authenticated(state: &AppState, id: &str, headers: &HeaderMap) -> Result<Installation, ApiError> {
    state
        .installations
        .authenticate(id, header(headers, "authorization"))
        .await?
        .ok_or_else(|| ApiError::bare(StatusCode::UNAUTHORIZED))
}

struct TokenUpdate<'a> {
    apns_token: &'a str,
    apns_environment: ApnsEnvironment,
    app_version: Option<&'a str>,
    os_version: Option<&'a str>,
}

fn read_token_update<'a>(validator: &mut Validator<'a>) -> Option<TokenUpdate<'a>> {
    let apns_token =
        validator.string("apnsToken", is_apns_token, "must match /^[0-9a-fA-F]{64,200}$/ regular expression");
    let apns_environment = validator
        .string(
            "apnsEnvironment",
            |value| ApnsEnvironment::parse(value).is_some(),
            "must be one of the following values: sandbox, production",
        )
        .and_then(ApnsEnvironment::parse);
    let app_version = validator.optional_string("appVersion", 0, 64);
    let os_version = validator.optional_string("osVersion", 0, 64);
    Some(TokenUpdate { apns_token: apns_token?, apns_environment: apns_environment?, app_version, os_version })
}

#[utoipa::path(
    post,
    path = "/api/v1/installations",
    tag = "Installations",
    params(("Idempotency-Key" = String, Header, description = "A UUID; a retry with the same key returns the same installation")),
    request_body(content = docs::CreateInstallation, content_type = "application/json"),
    responses((status = 201, body = InstallationCreated), (status = 400), (status = 401), (status = 409))
)]
pub async fn create(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Result<Response, ApiError> {
    let body = validation::body(body)?;
    let object = validation::json_object(&headers, &body)?;
    let mut validator = Validator::new(&object);
    let update = read_token_update(&mut validator);
    let attest_challenge = validator.optional_string("attestChallenge", 20, 128);
    validator.finish()?;
    let update = update.expect("validated");

    let idempotency_key = header(&headers, "idempotency-key")
        .filter(|key| validation::is_idempotency_key(key))
        .ok_or_else(|| ApiError::new(StatusCode::UNAUTHORIZED, "valid Idempotency-Key is required"))?;
    if let Some(cached) = state.installations.cached_creation(idempotency_key).await? {
        return Ok((StatusCode::CREATED, Json(cached)).into_response());
    }
    let key_id = state
        .app_attest
        .verify_request(
            &body,
            attest_challenge,
            header(&headers, "x-app-attest-key-id"),
            header(&headers, "x-app-attest-assertion"),
        )
        .await?;
    let created = state
        .installations
        .create(
            &NewInstallationRequest {
                apns_token: update.apns_token,
                apns_environment: update.apns_environment,
                app_version: update.app_version,
                os_version: update.os_version,
            },
            key_id.as_deref(),
            idempotency_key,
        )
        .await?;
    Ok((StatusCode::CREATED, Json(created)).into_response())
}

#[utoipa::path(
    put,
    path = "/api/v1/installations/{id}/apns-token",
    tag = "Installations",
    security(("bearer" = [])),
    params(("id" = Uuid, Path)),
    request_body(content = docs::UpdateApnsToken, content_type = "application/json"),
    responses((status = 204), (status = 400), (status = 401))
)]
pub async fn update_apns_token(
    State(state): State<AppState>,
    Path(id): Path<String>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Result<StatusCode, ApiError> {
    let body = validation::body(body)?;
    let object = validation::json_object(&headers, &body)?;
    let installation = authenticated(&state, &id, &headers).await?;
    let mut validator = Validator::new(&object);
    let update = read_token_update(&mut validator);
    validator.finish()?;
    let update = update.expect("validated");
    state
        .installations
        .update_apns_token(
            &installation,
            update.apns_token,
            update.apns_environment,
            update.app_version,
            update.os_version,
        )
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(
    post,
    path = "/api/v1/installations/{id}/telegram-subscriptions",
    tag = "Installations",
    security(("bearer" = [])),
    params(("id" = Uuid, Path)),
    responses((status = 201, body = TelegramSubscription), (status = 401))
)]
pub async fn rotate_subscription(
    State(state): State<AppState>,
    Path(id): Path<String>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    let installation = authenticated(&state, &id, &headers).await?;
    let subscription = state.installations.rotate_subscription(&installation).await?;
    Ok((StatusCode::CREATED, Json(subscription)).into_response())
}

#[utoipa::path(
    delete,
    path = "/api/v1/installations/{id}/telegram-subscriptions/{subscriptionId}",
    tag = "Installations",
    security(("bearer" = [])),
    params(("id" = Uuid, Path), ("subscriptionId" = Uuid, Path)),
    responses((status = 204), (status = 401), (status = 404))
)]
pub async fn delete_subscription(
    State(state): State<AppState>,
    Path((id, subscription_id)): Path<(String, String)>,
    headers: HeaderMap,
) -> Result<StatusCode, ApiError> {
    let installation = authenticated(&state, &id, &headers).await?;
    let subscription_id = Uuid::parse_str(&subscription_id).map_err(|_| ApiError::bare(StatusCode::NOT_FOUND))?;
    state.installations.delete_subscription(installation.id, subscription_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(
    delete,
    path = "/api/v1/installations/{id}",
    tag = "Installations",
    security(("bearer" = [])),
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 401))
)]
pub async fn delete_installation(
    State(state): State<AppState>,
    Path(id): Path<String>,
    headers: HeaderMap,
) -> Result<StatusCode, ApiError> {
    let installation = authenticated(&state, &id, &headers).await?;
    state.installations.delete_installation(installation.id).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub mod docs {
    /// Request body of `POST /api/v1/installations`.
    #[allow(dead_code)]
    #[derive(utoipa::ToSchema)]
    #[schema(rename_all = "camelCase")]
    pub struct CreateInstallation {
        /// Hex APNs device token, 64 to 200 characters.
        pub apns_token: String,
        #[schema(pattern = "sandbox|production")]
        pub apns_environment: String,
        pub app_version: Option<String>,
        pub os_version: Option<String>,
        /// A challenge from `GET /api/v1/app-attest/challenge` when App Attest is enforced.
        pub attest_challenge: Option<String>,
    }

    /// Request body of `PUT /api/v1/installations/{id}/apns-token`.
    #[allow(dead_code)]
    #[derive(utoipa::ToSchema)]
    #[schema(rename_all = "camelCase")]
    pub struct UpdateApnsToken {
        pub apns_token: String,
        #[schema(pattern = "sandbox|production")]
        pub apns_environment: String,
        pub app_version: Option<String>,
        pub os_version: Option<String>,
    }
}
