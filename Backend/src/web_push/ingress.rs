//! The public Web Push endpoint: it finds the subscription behind a capability token, checks the encryption
//! headers and size, and queues the ciphertext. It acknowledges only once the job is durably queued.

use std::sync::Arc;

use base64::Engine as _;
use sqlx::PgPool;
use time::OffsetDateTime;
use tracing::{info, warn};

use super::job::{ContentEncoding, EncryptionMetadata, TelegramWebPushJob};
use crate::db;
use crate::queue::Queue;
use crate::redis_store::{RateLimitError, RedisStore};
use crate::security::{base64url, hash_capability, sha256_hex};
use crate::telemetry::Metrics;

const DEDUPLICATION_TTL_SECONDS: u64 = 24 * 60 * 60;
const AES128GCM_MIN_BODY_BYTES: usize = 104;
const AESGCM_MIN_BODY_BYTES: usize = 19;
const MAX_BODY_BYTES: usize = 8192;

#[derive(Default)]
pub struct WebPushHeaders<'a> {
    pub content_encoding: Option<&'a str>,
    pub encryption: Option<&'a str>,
    pub crypto_key: Option<&'a str>,
}

#[derive(Debug, thiserror::Error)]
pub enum IngressError {
    /// Unknown, revoked or malformed endpoints and rejected bodies all look the same.
    #[error("not found")]
    NotFound,
    #[error("rate limit exceeded")]
    RateLimited,
    #[error("push queue is unavailable")]
    Unavailable,
}

impl From<RateLimitError> for IngressError {
    fn from(error: RateLimitError) -> Self {
        match error {
            RateLimitError::Exceeded => Self::RateLimited,
            RateLimitError::Redis(_) => Self::Unavailable,
        }
    }
}

#[derive(Clone)]
pub struct WebPushIngress {
    pub pool: PgPool,
    pub redis: RedisStore,
    pub queue: Queue,
    pub metrics: Arc<Metrics>,
}

pub fn is_capability_token(token: &str) -> bool {
    token.len() >= 40 && token.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
}

impl WebPushIngress {
    /// Accepts a push and returns the ciphertext digest for the receipt URL.
    pub async fn accept(
        &self,
        capability_token: &str,
        ciphertext: &[u8],
        headers: &WebPushHeaders<'_>,
        ip_address: &str,
    ) -> Result<String, IngressError> {
        if !is_capability_token(capability_token) {
            return Err(IngressError::NotFound);
        }
        self.redis.enforce_rate_limit(&format!("webpush:ip:{ip_address}"), 600, 60).await?;

        let subscription = db::find_subscription_by_endpoint(&self.pool, &hash_capability(capability_token))
            .await
            .map_err(|_| IngressError::Unavailable)?;
        let Some(subscription) = subscription.filter(|subscription| subscription.installation_status == "active")
        else {
            self.count("unknown_subscription");
            warn!(
                event = "webpush.unknown_subscription",
                contentEncoding = %headers.content_encoding.map(str::to_ascii_lowercase).as_deref().unwrap_or("missing"),
                bodyBytes = ciphertext.len(),
            );
            return Err(IngressError::NotFound);
        };

        let Ok(encryption) = parse_encryption_metadata(headers) else {
            self.count("unsupported_encoding");
            return Err(self.reject(
                &subscription.id,
                "invalid_encryption_metadata",
                headers.content_encoding,
                ciphertext.len(),
            ));
        };
        let minimum = match encryption.content_encoding {
            ContentEncoding::Aesgcm => AESGCM_MIN_BODY_BYTES,
            ContentEncoding::Aes128gcm => AES128GCM_MIN_BODY_BYTES,
        };
        if ciphertext.len() < minimum || ciphertext.len() > MAX_BODY_BYTES {
            self.count("invalid_size");
            return Err(self.reject(
                &subscription.id,
                "invalid_size",
                Some(encryption.content_encoding.as_str()),
                ciphertext.len(),
            ));
        }

        self.redis.enforce_rate_limit(&format!("webpush:subscription:{}", subscription.id), 120, 60).await?;

        let digest = sha256_hex(ciphertext);
        let deduplication_key = format!("webpush:dedupe:{}:{digest}", subscription.id);
        let first_delivery = self
            .redis
            .set_nx_ex(&deduplication_key, "1", DEDUPLICATION_TTL_SECONDS)
            .await
            .map_err(|_| IngressError::Unavailable)?;
        if !first_delivery {
            self.count("duplicate");
            return Ok(digest);
        }

        let received_at = OffsetDateTime::now_utc();
        let job = TelegramWebPushJob {
            subscription_id: subscription.id,
            ciphertext_base64: base64::engine::general_purpose::STANDARD.encode(ciphertext),
            encryption: encryption.clone(),
            received_at: crate::logging::iso_timestamp(received_at),
        };
        let job_id = format!("{}-{digest}", subscription.id);
        if self.queue.add(&job_id, &job).await.is_err() {
            let _ = self.redis.del(&[deduplication_key]).await;
            self.count("enqueue_failed");
            return Err(IngressError::Unavailable);
        }
        // The push is queued: a missed timestamp must not make Telegram send it again.
        if let Err(error) = db::mark_subscription_received(&self.pool, subscription.id, received_at).await {
            warn!(event = "webpush.receipt_time_failed", subscriptionId = %subscription.id, error = %error);
        }
        self.count("accepted");
        info!(
            event = "webpush.accepted",
            subscriptionId = %subscription.id,
            contentEncoding = encryption.content_encoding.as_str(),
            bodyBytes = ciphertext.len(),
        );
        Ok(digest)
    }

    fn count(&self, status: &'static str) {
        self.metrics.ingress.add(1, &[opentelemetry::KeyValue::new("status", status)]);
    }

    fn reject(
        &self,
        subscription_id: &uuid::Uuid,
        reason: &str,
        content_encoding: Option<&str>,
        body_bytes: usize,
    ) -> IngressError {
        warn!(
            event = "webpush.rejected",
            subscriptionId = %subscription_id,
            reason,
            contentEncoding = %content_encoding.map(str::to_ascii_lowercase).as_deref().unwrap_or("missing"),
            bodyBytes = body_bytes,
        );
        IngressError::NotFound
    }
}

/// Reads `Content-Encoding`, and for `aesgcm` the salt and record size from `Encryption` and the sender key from
/// `Crypto-Key`.
pub fn parse_encryption_metadata(headers: &WebPushHeaders<'_>) -> Result<EncryptionMetadata, &'static str> {
    let content_encoding = headers.content_encoding.map(|value| value.trim().to_ascii_lowercase());
    match content_encoding.as_deref() {
        Some("aes128gcm") => {
            return Ok(EncryptionMetadata {
                content_encoding: ContentEncoding::Aes128gcm,
                salt_base64url: None,
                sender_public_key_base64url: None,
                record_size: None,
            });
        }
        Some("aesgcm") => {}
        _ => return Err("unsupported content encoding"),
    }
    let salt = header_parameter(headers.encryption, "salt")?.ok_or("missing salt")?;
    let sender_public_key = header_parameter(headers.crypto_key, "dh")?.ok_or("missing dh")?;
    if decode_canonical_base64url(&salt)?.len() != 16 {
        return Err("invalid salt");
    }
    let sender_bytes = decode_canonical_base64url(&sender_public_key)?;
    if sender_bytes.len() != 65 || sender_bytes[0] != 4 {
        return Err("invalid sender public key");
    }
    let record_size = match header_parameter(headers.encryption, "rs")? {
        None => 4096,
        Some(value) => {
            value.parse::<usize>().ok().filter(|size| (19..=65_536).contains(size)).ok_or("invalid record size")?
        }
    };
    Ok(EncryptionMetadata {
        content_encoding: ContentEncoding::Aesgcm,
        salt_base64url: Some(salt),
        sender_public_key_base64url: Some(sender_public_key),
        record_size: Some(record_size),
    })
}

/// The value of `name=value` among `;`/`,`-separated parameters, unquoted. An empty value is an error.
fn header_parameter(header: Option<&str>, name: &str) -> Result<Option<String>, &'static str> {
    let Some(header) = header else { return Ok(None) };
    let Some(parameter) = header.split([';', ',']).map(str::trim).find(|part| {
        let key = part.split_once('=').map_or(*part, |(key, _)| key);
        key.trim().eq_ignore_ascii_case(name)
    }) else {
        return Ok(None);
    };
    let mut value = parameter.split_once('=').map_or("", |(_, value)| value).trim();
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        value = &value[1..value.len() - 1];
    }
    if value.is_empty() { Err("empty parameter") } else { Ok(Some(value.to_owned())) }
}

/// Base64url that re-encodes to itself, with optional padding.
fn decode_canonical_base64url(value: &str) -> Result<Vec<u8>, &'static str> {
    let unpadded = value.trim_end_matches('=');
    if unpadded.is_empty()
        || value.len() - unpadded.len() > 2
        || !unpadded.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
    {
        return Err("invalid base64url");
    }
    let decoded = base64url::decode(unpadded).map_err(|_| "invalid base64url")?;
    if base64url::encode(&decoded) != unpadded {
        return Err("non-canonical base64url");
    }
    Ok(decoded)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_aes128gcm_without_parameters() {
        let headers = WebPushHeaders { content_encoding: Some("AES128GCM "), ..Default::default() };
        assert_eq!(parse_encryption_metadata(&headers).unwrap().content_encoding, ContentEncoding::Aes128gcm);
    }

    #[test]
    fn normalizes_legacy_aesgcm_headers_for_the_worker() {
        let salt = base64url::encode([3u8; 16]);
        let mut sender = vec![4u8];
        sender.extend([5u8; 64]);
        let sender = base64url::encode(sender);
        let encryption = format!("salt={salt}; rs=4096");
        let crypto_key = format!("dh={sender}");
        let headers = WebPushHeaders {
            content_encoding: Some("aesgcm"),
            encryption: Some(&encryption),
            crypto_key: Some(&crypto_key),
        };
        assert_eq!(
            parse_encryption_metadata(&headers).unwrap(),
            EncryptionMetadata {
                content_encoding: ContentEncoding::Aesgcm,
                salt_base64url: Some(salt.clone()),
                sender_public_key_base64url: Some(sender.clone()),
                record_size: Some(4096),
            }
        );
        let quoted = format!("keyid=\"p256dh\"; dh=\"{sender}\"");
        let default_size = format!("salt=\"{salt}\"");
        let headers = WebPushHeaders { encryption: Some(&default_size), crypto_key: Some(&quoted), ..headers };
        assert_eq!(parse_encryption_metadata(&headers).unwrap().record_size, Some(4096));
    }

    #[test]
    fn rejects_bad_legacy_parameters() {
        let salt = base64url::encode([3u8; 16]);
        let sender = base64url::encode([4u8; 65]);
        let crypto_key = format!("dh={sender}");
        for encryption in
            [format!("salt={salt}; rs=18"), format!("salt={salt}x"), "rs=4096".to_owned(), "salt=".to_owned()]
        {
            let headers = WebPushHeaders {
                content_encoding: Some("aesgcm"),
                encryption: Some(&encryption),
                crypto_key: Some(&crypto_key),
            };
            assert!(parse_encryption_metadata(&headers).is_err(), "{encryption}");
        }
        assert!(
            parse_encryption_metadata(&WebPushHeaders { content_encoding: Some("gzip"), ..Default::default() })
                .is_err()
        );
        assert!(parse_encryption_metadata(&WebPushHeaders::default()).is_err());
    }

    #[test]
    fn recognizes_capability_tokens() {
        assert!(is_capability_token(&"a".repeat(43)));
        assert!(!is_capability_token(&"a".repeat(39)));
        assert!(!is_capability_token(&format!("{}!", "a".repeat(43))));
    }
}
