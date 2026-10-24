//! A decrypted payload the Notification Service Extension fetches once with the token from the alert, then gone.

use serde_json::Value;
use tracing::info;

use crate::redis_store::RedisStore;

const CONTENT_TTL_SECONDS: u64 = 15 * 60;
const CONTENT_KEY_PREFIX: &str = "notification-content:";

#[derive(Clone)]
pub struct NotificationContentStore {
    redis: RedisStore,
}

pub fn is_content_token(token: &str) -> bool {
    token.len() == 43 && token.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
}

impl NotificationContentStore {
    pub fn new(redis: RedisStore) -> Self {
        Self { redis }
    }

    pub async fn put(&self, payload: &Value) -> redis::RedisResult<String> {
        let token = crate::security::random_token();
        self.redis.set_ex(&format!("{CONTENT_KEY_PREFIX}{token}"), &payload.to_string(), CONTENT_TTL_SECONDS).await?;
        Ok(token)
    }

    pub async fn take(&self, token: &str) -> redis::RedisResult<Option<Value>> {
        if !is_content_token(token) {
            return Ok(None);
        }
        let Some(stored) = self.redis.get_del(&format!("{CONTENT_KEY_PREFIX}{token}")).await? else {
            return Ok(None);
        };
        let Ok(payload) = serde_json::from_str::<Value>(&stored) else { return Ok(None) };
        info!(
            event = "notification_content.consumed",
            locKey = payload["data"]["loc_key"].as_str().unwrap_or_default(),
        );
        Ok(Some(payload))
    }
}
