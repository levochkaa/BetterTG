//! `/health/live` for the process, `/health/ready` for PostgreSQL and Redis as well.

use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use serde_json::{Value, json};

use super::{ApiError, AppState};
use crate::db;

pub async fn live() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

pub async fn ready(State(state): State<AppState>) -> Result<Json<Value>, ApiError> {
    let (database, redis) = tokio::join!(db::ping(&state.pool), state.redis.ping());
    match (database, redis) {
        (Ok(()), Ok(())) => Ok(Json(json!({ "status": "ok" }))),
        _ => Err(ApiError::new(StatusCode::SERVICE_UNAVAILABLE, "dependencies are unavailable")),
    }
}
