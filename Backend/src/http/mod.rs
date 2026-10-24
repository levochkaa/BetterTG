//! The API process's HTTP interface. Responses, status codes and error bodies match the NestJS backend the iOS
//! app was written against.

mod app_attest;
mod docs;
mod health;
mod installations;
mod validation;
mod web_push;

use std::net::SocketAddr;
use std::sync::Arc;

use axum::Router;
use axum::extract::{ConnectInfo, DefaultBodyLimit, FromRequestParts, MatchedPath, Request};
use axum::http::request::Parts;
use axum::http::{HeaderName, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use serde_json::{Value, json};
use sqlx::PgPool;
use tower_http::set_header::SetResponseHeaderLayer;
use tower_http::trace::TraceLayer;
use tracing::error;

use crate::app_attest::AppAttestService;
use crate::config::Environment;
use crate::installations::InstallationsService;
use crate::redis_store::RedisStore;
use crate::web_push::content_store::NotificationContentStore;
use crate::web_push::ingress::WebPushIngress;

#[derive(Clone)]
pub struct AppState {
    pub environment: Arc<Environment>,
    pub pool: PgPool,
    pub redis: RedisStore,
    pub installations: InstallationsService,
    pub app_attest: AppAttestService,
    pub ingress: WebPushIngress,
    pub content_store: NotificationContentStore,
}

/// An error in Nest's shape: `{"message", "error", "statusCode"}`.
#[derive(Debug)]
pub struct ApiError {
    status: StatusCode,
    message: Value,
    error: Option<&'static str>,
}

impl ApiError {
    pub fn new(status: StatusCode, message: impl Into<String>) -> Self {
        Self { status, message: Value::String(message.into()), error: status.canonical_reason() }
    }

    /// An exception raised without a message: the reason phrase alone, as Nest reports it.
    pub fn bare(status: StatusCode) -> Self {
        Self { status, message: Value::String(status.canonical_reason().unwrap_or_default().to_owned()), error: None }
    }

    pub fn validation(messages: Vec<String>) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            message: Value::Array(messages.into_iter().map(Value::String).collect()),
            error: Some("Bad Request"),
        }
    }

    pub fn rate_limited() -> Self {
        Self { status: StatusCode::TOO_MANY_REQUESTS, message: json!("rate limit exceeded"), error: None }
    }

    /// Logs the cause and answers like Nest's unhandled-exception filter.
    pub fn internal(cause: impl std::fmt::Display) -> Self {
        error!(event = "http.unhandled_error", error = %cause);
        Self { status: StatusCode::INTERNAL_SERVER_ERROR, message: json!("Internal server error"), error: None }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let mut body = serde_json::Map::new();
        body.insert("message".to_owned(), self.message);
        if let Some(error) = self.error {
            body.insert("error".to_owned(), Value::String(error.to_owned()));
        }
        body.insert("statusCode".to_owned(), Value::from(self.status.as_u16()));
        (self.status, axum::Json(Value::Object(body))).into_response()
    }
}

/// The client address: the leftmost `X-Forwarded-For` entry, as Express reports it behind a trusted proxy,
/// else the peer.
pub struct ClientIp(pub String);

impl<S: Send + Sync> FromRequestParts<S> for ClientIp {
    type Rejection = std::convert::Infallible;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        let forwarded = parts
            .headers
            .get("x-forwarded-for")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.split(',').map(str::trim).find(|entry| !entry.is_empty()));
        if let Some(address) = forwarded {
            return Ok(Self(address.to_owned()));
        }
        let peer = parts.extensions.get::<ConnectInfo<SocketAddr>>().map(|info| info.0.ip().to_string());
        Ok(Self(peer.unwrap_or_else(|| "unknown".to_owned())))
    }
}

async fn not_found(request: Request) -> ApiError {
    ApiError::new(StatusCode::NOT_FOUND, format!("Cannot {} {}", request.method(), request.uri().path()))
}

/// Helmet's default response headers.
const SECURITY_HEADERS: &[(&str, &str)] = &[
    (
        "content-security-policy",
        "default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';\
         img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';\
         style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests",
    ),
    ("cross-origin-opener-policy", "same-origin"),
    ("cross-origin-resource-policy", "same-origin"),
    ("origin-agent-cluster", "?1"),
    ("referrer-policy", "no-referrer"),
    ("strict-transport-security", "max-age=31536000; includeSubDomains"),
    ("x-content-type-options", "nosniff"),
    ("x-dns-prefetch-control", "off"),
    ("x-download-options", "noopen"),
    ("x-frame-options", "SAMEORIGIN"),
    ("x-permitted-cross-domain-policies", "none"),
    ("x-xss-protection", "0"),
];

pub fn router(state: AppState) -> Router {
    let swagger_enabled = state.environment.swagger_enabled;
    let mut router = Router::new()
        .route("/health/live", get(health::live))
        .route("/health/ready", get(health::ready))
        .route("/api/v1/app-attest/challenge", get(app_attest::challenge))
        .route("/api/v1/app-attest/attestations", post(app_attest::attestations))
        .route("/api/v1/installations", post(installations::create))
        .route("/api/v1/installations/{id}", delete(installations::delete_installation))
        .route("/api/v1/installations/{id}/apns-token", put(installations::update_apns_token))
        .route("/api/v1/installations/{id}/telegram-subscriptions", post(installations::rotate_subscription))
        .route(
            "/api/v1/installations/{id}/telegram-subscriptions/{subscription_id}",
            delete(installations::delete_subscription),
        )
        .route("/webpush/v1/{capability_token}", post(web_push::accept).layer(DefaultBodyLimit::max(8 * 1024)))
        .route("/notification-content/v1/{token}", get(web_push::notification_content));
    if swagger_enabled {
        router = router.merge(docs::router());
    }
    let mut router = router
        .fallback(not_found)
        .method_not_allowed_fallback(not_found)
        .layer(DefaultBodyLimit::max(64 * 1024))
        .layer(TraceLayer::new_for_http().make_span_with(|request: &Request| {
            // The route template, never the path: capability and content tokens must not reach telemetry.
            let route = request.extensions().get::<MatchedPath>().map_or("unmatched", MatchedPath::as_str);
            tracing::info_span!("http.request", method = %request.method(), route)
        }))
        .with_state(state);
    for (name, value) in SECURITY_HEADERS {
        router = router.layer(SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static(name),
            HeaderValue::from_static(value),
        ));
    }
    router
}
