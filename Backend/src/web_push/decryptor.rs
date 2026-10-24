//! Opens a queued Web Push with its subscription's stored secrets and reads the Telegram payload inside.

use super::ece::{self, EceError, LegacyParameters};
use super::job::{ContentEncoding, EncryptionMetadata};
use super::payload::{TelegramPushPayload, parse_telegram_push_payload};
use crate::db::Subscription;
use crate::security::{SecretBox, base64url};

/// A push that can't be decrypted or read; `reason` names the failure for the metric.
#[derive(Debug, thiserror::Error)]
#[error("invalid encrypted Web Push payload: {reason}")]
pub struct InvalidWebPushPayload {
    pub reason: &'static str,
}

impl From<EceError> for InvalidWebPushPayload {
    fn from(error: EceError) -> Self {
        Self { reason: error.reason() }
    }
}

const MAXIMUM_PLAINTEXT_BYTES: usize = 4096;

pub fn private_key_context(subscription_id: &uuid::Uuid) -> String {
    format!("telegram-subscription:{subscription_id}:private-key")
}

pub fn auth_secret_context(subscription_id: &uuid::Uuid) -> String {
    format!("telegram-subscription:{subscription_id}:auth-secret")
}

pub fn decrypt_bytes(
    secret_box: &SecretBox,
    subscription: &Subscription,
    ciphertext: &[u8],
    encryption: &EncryptionMetadata,
) -> Result<Vec<u8>, InvalidWebPushPayload> {
    let key_material = |_| InvalidWebPushPayload::from(EceError::InvalidKeyMaterial);
    let private_key = secret_box
        .decrypt(&subscription.p256dh_private_key_encrypted, &private_key_context(&subscription.id))
        .map_err(key_material)?;
    let auth_secret = secret_box
        .decrypt(&subscription.auth_secret_encrypted, &auth_secret_context(&subscription.id))
        .map_err(key_material)?;
    let receiver = ece::parse_private_key(&private_key)?;
    match encryption.content_encoding {
        ContentEncoding::Aes128gcm => Ok(ece::decrypt_aes128gcm(&receiver, &auth_secret, ciphertext)?),
        ContentEncoding::Aesgcm => {
            let (Some(salt), Some(sender)) = (&encryption.salt_base64url, &encryption.sender_public_key_base64url)
            else {
                return Err(EceError::InvalidKeyMaterial.into());
            };
            let salt = base64url::decode(salt).map_err(|_| EceError::InvalidKeyMaterial)?;
            let sender = base64url::decode(sender).map_err(|_| EceError::InvalidKeyMaterial)?;
            let parameters = LegacyParameters {
                salt: &salt,
                sender_public_key: &sender,
                record_size: encryption.record_size.unwrap_or(4096),
            };
            Ok(ece::decrypt_aesgcm(&receiver, &auth_secret, &parameters, ciphertext)?)
        }
    }
}

/// Reads text as JavaScript's `JSON.parse` would after Node decoded the bytes: a `\uD800`–`\uDFFF` escape that
/// isn't half of a surrogate pair, such as an emoji cut off at a preview limit, becomes U+FFFD instead of failing.
fn replace_lone_surrogate_escapes(text: &str) -> std::borrow::Cow<'_, str> {
    fn escape_at(bytes: &[u8], index: usize) -> Option<u16> {
        let digits = bytes.get(index..index + 6)?;
        if digits[0] != b'\\' || digits[1] != b'u' {
            return None;
        }
        u16::from_str_radix(std::str::from_utf8(&digits[2..]).ok()?, 16).ok()
    }
    if !text.contains("\\u") {
        return std::borrow::Cow::Borrowed(text);
    }
    let bytes = text.as_bytes();
    let mut output = String::with_capacity(text.len());
    let mut index = 0;
    let mut copied = 0;
    while index < bytes.len() {
        if bytes[index] != b'\\' {
            index += 1;
            continue;
        }
        let Some(unit) = escape_at(bytes, index) else {
            // Another escape, such as `\\`, which must not be read as the start of `\u`.
            index += 2;
            continue;
        };
        let lone = match unit {
            0xD800..=0xDBFF => match escape_at(bytes, index + 6) {
                Some(0xDC00..=0xDFFF) => {
                    index += 12;
                    continue;
                }
                _ => true,
            },
            0xDC00..=0xDFFF => true,
            _ => false,
        };
        if lone {
            output.push_str(&text[copied..index]);
            output.push_str("\\uFFFD");
            copied = index + 6;
        }
        index += 6;
    }
    output.push_str(&text[copied..]);
    std::borrow::Cow::Owned(output)
}

pub fn decrypt_telegram_payload(
    secret_box: &SecretBox,
    subscription: &Subscription,
    ciphertext: &[u8],
    encryption: &EncryptionMetadata,
) -> Result<TelegramPushPayload, InvalidWebPushPayload> {
    let plaintext = decrypt_bytes(secret_box, subscription, ciphertext, encryption)?;
    if plaintext.len() > MAXIMUM_PLAINTEXT_BYTES {
        return Err(InvalidWebPushPayload { reason: "plaintext_too_large" });
    }
    let decoded = String::from_utf8_lossy(&plaintext);
    let text = replace_lone_surrogate_escapes(&decoded);
    let value: serde_json::Value =
        serde_json::from_str(&text).map_err(|_| InvalidWebPushPayload { reason: "invalid_json" })?;
    parse_telegram_push_payload(&value).map_err(|_| InvalidWebPushPayload { reason: "invalid_payload" })
}

#[cfg(test)]
mod tests {
    use p256::SecretKey;
    use rand::rngs::OsRng;
    use uuid::Uuid;

    use super::*;
    use crate::security::tests::test_secret_box;

    fn subscription(secret_box: &SecretBox, private_key: &[u8], auth_secret: &[u8]) -> Subscription {
        let id = Uuid::new_v4();
        Subscription {
            id,
            installation_id: Uuid::new_v4(),
            p256dh_private_key_encrypted: secret_box.encrypt(private_key, &private_key_context(&id)),
            auth_secret_encrypted: secret_box.encrypt(auth_secret, &auth_secret_context(&id)),
            installation_status: "active".to_owned(),
        }
    }

    const MODERN: EncryptionMetadata = EncryptionMetadata {
        content_encoding: ContentEncoding::Aes128gcm,
        salt_base64url: None,
        sender_public_key_base64url: None,
        record_size: None,
    };

    #[test]
    fn reads_payloads_cut_inside_a_character_like_node() {
        assert_eq!(replace_lone_surrogate_escapes(r#"{"a":"x\ud83d"}"#), r#"{"a":"x\uFFFD"}"#);
        assert_eq!(replace_lone_surrogate_escapes(r#"{"a":"\ude00\ud83d\ude00"}"#), r#"{"a":"\uFFFD\ud83d\ude00"}"#);
        assert_eq!(replace_lone_surrogate_escapes(r#"{"a":"\\ud83d"}"#), r#"{"a":"\\ud83d"}"#);
        let secret_box = test_secret_box();
        let receiver = SecretKey::random(&mut OsRng);
        let subscription = subscription(&secret_box, &receiver.to_bytes(), &[1; 16]);
        let mut plaintext = br#"{"loc_key":"MESSAGE_TEXT","loc_args":["Alice","Hi \ud83d"],"description":""#.to_vec();
        plaintext.extend([0xF0, 0x9F, b'"', b'}']);
        let ciphertext = ece::encrypt_aes128gcm(
            &plaintext,
            &SecretKey::random(&mut OsRng),
            &receiver.public_key(),
            &[1; 16],
            &[2; 16],
            4096,
        );
        let payload = decrypt_telegram_payload(&secret_box, &subscription, &ciphertext, &MODERN).unwrap();
        assert_eq!(payload.data.loc_args[1], "Hi \u{FFFD}");
        assert_eq!(payload.data.description.as_deref(), Some("\u{FFFD}"));
    }

    #[test]
    fn decrypts_an_rfc_8291_message_with_stored_receiver_secrets() {
        let secret_box = test_secret_box();
        let subscription = subscription(
            &secret_box,
            &base64url::decode("q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94").unwrap(),
            &base64url::decode("BTBZMqHH6r4Tts7J_aSIgg").unwrap(),
        );
        let ciphertext = base64url::decode(
            "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN",
        )
        .unwrap();
        assert_eq!(
            decrypt_bytes(&secret_box, &subscription, &ciphertext, &MODERN).unwrap(),
            b"When I grow up, I want to be a watermelon"
        );
    }

    #[test]
    fn parses_a_synthetic_telegram_payload_and_rejects_tampering() {
        let secret_box = test_secret_box();
        let receiver = SecretKey::random(&mut OsRng);
        let sender = SecretKey::random(&mut OsRng);
        let auth_secret = [7u8; 16];
        let subscription = subscription(&secret_box, &receiver.to_bytes(), &auth_secret);
        let plaintext =
            br#"{"data":{"loc_key":"MESSAGE_TEXT","loc_args":["Alice","Hello"],"custom":{"from_id":1,"msg_id":2}}}"#;
        let mut ciphertext =
            ece::encrypt_aes128gcm(plaintext, &sender, &receiver.public_key(), &auth_secret, &[1; 16], 4096);
        assert_eq!(
            decrypt_telegram_payload(&secret_box, &subscription, &ciphertext, &MODERN).unwrap().data.loc_key,
            "MESSAGE_TEXT"
        );
        let last = ciphertext.len() - 1;
        ciphertext[last] ^= 1;
        assert_eq!(
            decrypt_telegram_payload(&secret_box, &subscription, &ciphertext, &MODERN).unwrap_err().reason,
            "authentication_failed"
        );
    }

    #[test]
    fn decrypts_legacy_aesgcm_with_parameters_from_headers() {
        let secret_box = test_secret_box();
        let receiver = SecretKey::random(&mut OsRng);
        let sender = SecretKey::random(&mut OsRng);
        let auth_secret = crate::security::random_bytes::<16>();
        let salt = crate::security::random_bytes::<16>();
        let subscription = subscription(&secret_box, &receiver.to_bytes(), &auth_secret);
        let plaintext = br#"{"data":{"loc_key":"MESSAGE_TEXT","loc_args":["Alice","Legacy payload"],"custom":{"from_id":1,"msg_id":3}}}"#;
        let ciphertext = ece::encrypt_aesgcm(plaintext, &sender, &receiver.public_key(), &auth_secret, &salt, 4096);
        let metadata = EncryptionMetadata {
            content_encoding: ContentEncoding::Aesgcm,
            salt_base64url: Some(base64url::encode(salt)),
            sender_public_key_base64url: Some(base64url::encode(ece::public_key_bytes(&sender))),
            record_size: Some(4096),
        };
        let payload = decrypt_telegram_payload(&secret_box, &subscription, &ciphertext, &metadata).unwrap();
        assert_eq!(payload.data.loc_key, "MESSAGE_TEXT");
        assert_eq!(payload.data.loc_args, ["Alice", "Legacy payload"]);
    }
}
