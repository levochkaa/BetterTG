//! Application-level encryption of stored secrets and the hashes that stand in for bearer and capability tokens.
//!
//! An encrypted value is `v1.<key id>.<iv>.<tag>.<ciphertext>` with base64url parts: AES-256-GCM under a key from
//! the keyring, bound to an associated-data string that names the row and column it belongs to.

use std::collections::HashMap;

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine as _;
use hmac::{Hmac, Mac};
use rand::RngCore;
use rand::rngs::OsRng;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

pub mod base64url {
    use base64::Engine as _;
    use base64::alphabet;
    use base64::engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig};

    const LENIENT: GeneralPurpose = GeneralPurpose::new(
        &alphabet::URL_SAFE,
        GeneralPurposeConfig::new().with_encode_padding(false).with_decode_padding_mode(DecodePaddingMode::Indifferent),
    );

    pub fn encode(bytes: impl AsRef<[u8]>) -> String {
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
    }

    /// Accepts padded and unpadded input.
    pub fn decode(value: &str) -> Result<Vec<u8>, base64::DecodeError> {
        LENIENT.decode(value)
    }
}

/// Standard base64 as Node's `Buffer.from(value, 'base64')` reads it: either alphabet, padding optional.
pub fn decode_base64_lenient(value: &str) -> Option<Vec<u8>> {
    let normalized: String = value
        .chars()
        .filter(|character| !character.is_whitespace())
        .map(|character| match character {
            '-' => '+',
            '_' => '/',
            other => other,
        })
        .collect();
    let unpadded = normalized.trim_end_matches('=');
    base64::engine::general_purpose::STANDARD_NO_PAD.decode(unpadded).ok()
}

#[derive(Debug, thiserror::Error)]
pub enum SecretBoxError {
    #[error("encrypted value has an invalid envelope")]
    InvalidEnvelope,
    #[error("encryption key {0} is unavailable")]
    UnknownKey(String),
    #[error("encrypted value failed authentication")]
    Authentication,
}

pub struct SecretBox {
    current_key_id: String,
    keys: HashMap<String, Aes256Gcm>,
    management_token_pepper: Vec<u8>,
}

impl SecretBox {
    pub fn new(current_key_id: &str, keyring: &str, management_token_pepper: &str) -> anyhow::Result<Self> {
        let mut keys = HashMap::new();
        for entry in keyring.split(',').map(str::trim) {
            let Some((key_id, encoded)) = entry.split_once(':').filter(|(key_id, _)| !key_id.is_empty()) else {
                anyhow::bail!("ENCRYPTION_KEYS contains an invalid entry");
            };
            if keys.contains_key(key_id) {
                anyhow::bail!("duplicate encryption key id {key_id}");
            }
            let key = decode_key(encoded, &format!("ENCRYPTION_KEYS:{key_id}"))?;
            keys.insert(key_id.to_owned(), Aes256Gcm::new_from_slice(&key).expect("32-byte key"));
        }
        if !keys.contains_key(current_key_id) {
            anyhow::bail!("ENCRYPTION_CURRENT_KEY_ID {current_key_id} is missing from keyring");
        }
        Ok(Self {
            current_key_id: current_key_id.to_owned(),
            keys,
            management_token_pepper: decode_key(management_token_pepper, "MANAGEMENT_TOKEN_PEPPER")?,
        })
    }

    pub fn encrypt(&self, value: impl AsRef<[u8]>, associated_data: &str) -> String {
        let cipher = &self.keys[&self.current_key_id];
        let mut iv = [0u8; 12];
        OsRng.fill_bytes(&mut iv);
        let sealed = cipher
            .encrypt(&Nonce::from(iv), Payload { msg: value.as_ref(), aad: associated_data.as_bytes() })
            .expect("AES-GCM encryption");
        let (ciphertext, tag) = sealed.split_at(sealed.len() - 16);
        ["v1", &self.current_key_id, &base64url::encode(iv), &base64url::encode(tag), &base64url::encode(ciphertext)]
            .join(".")
    }

    pub fn decrypt(&self, value: &str, associated_data: &str) -> Result<Vec<u8>, SecretBoxError> {
        let parts: Vec<&str> = value.split('.').collect();
        let [version, key_id, iv, tag, ciphertext] = parts[..] else { return Err(SecretBoxError::InvalidEnvelope) };
        if version != "v1" || key_id.is_empty() || iv.is_empty() || tag.is_empty() {
            return Err(SecretBoxError::InvalidEnvelope);
        }
        let cipher = self.keys.get(key_id).ok_or_else(|| SecretBoxError::UnknownKey(key_id.to_owned()))?;
        let iv = base64url::decode(iv).map_err(|_| SecretBoxError::InvalidEnvelope)?;
        let tag = base64url::decode(tag).map_err(|_| SecretBoxError::InvalidEnvelope)?;
        let mut sealed = base64url::decode(ciphertext).map_err(|_| SecretBoxError::InvalidEnvelope)?;
        let (Ok(iv), 16) = (<[u8; 12]>::try_from(iv), tag.len()) else {
            return Err(SecretBoxError::InvalidEnvelope);
        };
        sealed.extend_from_slice(&tag);
        cipher
            .decrypt(&Nonce::from(iv), Payload { msg: &sealed, aad: associated_data.as_bytes() })
            .map_err(|_| SecretBoxError::Authentication)
    }

    /// HMAC-SHA-256 of a bearer token under the management pepper, in hex.
    pub fn hash_management_token(&self, token: &str) -> String {
        let mut mac =
            <Hmac<Sha256> as Mac>::new_from_slice(&self.management_token_pepper).expect("HMAC accepts any key");
        mac.update(token.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }
}

/// SHA-256 of a capability token, in hex.
pub fn hash_capability(token: &str) -> String {
    sha256_hex(token.as_bytes())
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

/// 32 random bytes in base64url, 43 characters.
pub fn random_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    base64url::encode(bytes)
}

pub fn random_bytes<const N: usize>() -> [u8; N] {
    let mut bytes = [0u8; N];
    OsRng.fill_bytes(&mut bytes);
    bytes
}

/// Compares two hex digests in constant time.
pub fn secure_hash_matches(expected_hex: &str, actual_hex: &str) -> bool {
    match (hex::decode(expected_hex.trim()), hex::decode(actual_hex.trim())) {
        (Ok(expected), Ok(actual)) => expected.len() == actual.len() && bool::from(expected.ct_eq(&actual)),
        _ => false,
    }
}

fn decode_key(value: &str, field: &str) -> anyhow::Result<Vec<u8>> {
    match decode_base64_lenient(value) {
        Some(key) if key.len() == 32 => Ok(key),
        _ => anyhow::bail!("{field} must contain exactly 32 bytes"),
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub fn test_secret_box() -> SecretBox {
        SecretBox::new(
            "test",
            "test:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=",
            "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=",
        )
        .unwrap()
    }

    fn rotated() -> SecretBox {
        SecretBox::new(
            "v2",
            "v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=,v2:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=",
            "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=",
        )
        .unwrap()
    }

    #[test]
    fn encrypts_with_associated_data_and_decrypts_with_the_keyring() {
        let secret_box = rotated();
        let encrypted = secret_box.encrypt("private", "installation:1:apns");
        assert!(encrypted.starts_with("v1.v2."));
        assert_eq!(secret_box.decrypt(&encrypted, "installation:1:apns").unwrap(), b"private");
        assert!(secret_box.decrypt(&encrypted, "installation:2:apns").is_err());
    }

    #[test]
    fn reads_values_written_by_the_node_backend() {
        // Node's createCipheriv('aes-256-gcm') with the v2 key, as the NestJS SecretBoxService stored rows.
        let secret_box = rotated();
        let stored = "v1.v2.CQkJCQkJCQkJCQkJ.xXwL3SrjA6Sbn0o7e6N0HQ.xA4lMQ";
        assert_eq!(secret_box.decrypt(stored, "telegram-subscription:x:auth-secret").unwrap(), [0, 1, 2, 255]);
        // createHmac('sha256', pepper).update('token').digest('hex')
        assert_eq!(
            secret_box.hash_management_token("token"),
            "8cd54d6dcf0d8f9efcdb6f8c971029402ff19aa3108fca9b9f76311e7aafa6a3"
        );
    }

    #[test]
    fn decrypts_with_a_retired_key() {
        let old = SecretBox::new(
            "v1",
            "v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=",
        )
        .unwrap();
        let encrypted = old.encrypt("legacy", "context");
        assert_eq!(rotated().decrypt(&encrypted, "context").unwrap(), b"legacy");
    }

    #[test]
    fn rejects_bad_keyrings_and_envelopes() {
        assert!(SecretBox::new("v1", "v1:AAAA", "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=").is_err());
        assert!(SecretBox::new("v2", "v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", "AgIC").is_err());
        let secret_box = test_secret_box();
        assert!(secret_box.decrypt("v2.test.a.b.c", "x").is_err());
        assert!(secret_box.decrypt("v1.other.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAA.", "x").is_err());
    }

    #[test]
    fn produces_stable_domain_specific_token_hashes() {
        let secret_box = test_secret_box();
        assert_eq!(secret_box.hash_management_token("token"), secret_box.hash_management_token("token"));
        assert_ne!(secret_box.hash_management_token("token"), hash_capability("token"));
        assert!(secure_hash_matches(&hash_capability("token"), &hash_capability("token")));
        assert!(!secure_hash_matches(&hash_capability("token"), &hash_capability("other")));
        assert_eq!(random_token().len(), 43);
    }
}
