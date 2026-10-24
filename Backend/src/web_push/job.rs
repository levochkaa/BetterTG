//! The queued job: ciphertext and the encryption parameters it needs, nothing decrypted.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::queue::RetryPolicy;

pub const TELEGRAM_WEB_PUSH_QUEUE: &str = "telegram-web-push";

/// Five attempts, exponential backoff from one second with half jitter; failed jobs stay an hour, at most 100.
pub const RETRY_POLICY: RetryPolicy = RetryPolicy {
    attempts: 5,
    base_delay: std::time::Duration::from_secs(1),
    jitter: 0.5,
    keep_failed_for: std::time::Duration::from_secs(3600),
    keep_failed_count: 100,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContentEncoding {
    Aes128gcm,
    Aesgcm,
}

impl ContentEncoding {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Aes128gcm => "aes128gcm",
            Self::Aesgcm => "aesgcm",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EncryptionMetadata {
    pub content_encoding: ContentEncoding,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub salt_base64url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender_public_key_base64url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub record_size: Option<usize>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TelegramWebPushJob {
    pub subscription_id: Uuid,
    pub ciphertext_base64: String,
    pub encryption: EncryptionMetadata,
    pub received_at: String,
}
