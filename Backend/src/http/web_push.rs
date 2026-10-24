//! Telegram's Web Push ingress and the one-time notification content the Notification Service Extension reads.

use axum::Json;
use axum::extract::rejection::BytesRejection;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;

use super::validation;
use super::{ApiError, AppState, ClientIp};
use crate::redis_store::RateLimitError;
use crate::web_push::ingress::{IngressError, WebPushHeaders};

fn header(headers: &HeaderMap, name: header::HeaderName) -> Option<&str> {
    headers.get(name).and_then(|value| value.to_str().ok())
}

pub async fn accept(
    State(state): State<AppState>,
    Path(capability_token): Path<String>,
    ClientIp(ip): ClientIp,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Result<Response, ApiError> {
    let body = validation::body(body)?;
    let push_headers = WebPushHeaders {
        content_encoding: header(&headers, header::CONTENT_ENCODING),
        encryption: header(&headers, header::HeaderName::from_static("encryption")),
        crypto_key: header(&headers, header::HeaderName::from_static("crypto-key")),
    };
    match state.ingress.accept(&capability_token, &body, &push_headers, &ip).await {
        Ok(digest) => {
            let location = HeaderValue::from_str(&format!("/webpush/receipts/{digest}")).expect("hex digest");
            Ok((StatusCode::CREATED, [(header::LOCATION, location)]).into_response())
        }
        Err(IngressError::NotFound) => Err(ApiError::bare(StatusCode::NOT_FOUND)),
        Err(IngressError::RateLimited) => Err(ApiError::rate_limited()),
        Err(IngressError::Unavailable) => {
            Err(ApiError::new(StatusCode::SERVICE_UNAVAILABLE, "push queue is unavailable"))
        }
    }
}

pub async fn notification_content(
    State(state): State<AppState>,
    Path(token): Path<String>,
    ClientIp(ip): ClientIp,
) -> Result<Response, ApiError> {
    match state.redis.enforce_rate_limit(&format!("notification-content:ip:{ip}"), 120, 60).await {
        Ok(()) => {}
        Err(RateLimitError::Exceeded) => return Err(ApiError::rate_limited()),
        Err(RateLimitError::Redis(error)) => return Err(ApiError::internal(error)),
    }
    let payload = state.content_store.take(&token).await.map_err(ApiError::internal)?;
    let payload = payload.ok_or_else(|| ApiError::bare(StatusCode::NOT_FOUND))?;
    Ok(([(header::CACHE_CONTROL, HeaderValue::from_static("no-store"))], Json(payload)).into_response())
}
