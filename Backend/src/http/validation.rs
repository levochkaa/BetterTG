//! JSON bodies read as Express's `json()` parser and Nest's whitelisting `ValidationPipe` read them.

use axum::extract::rejection::BytesRejection;
use axum::http::{HeaderMap, StatusCode, header};
use bytes::Bytes;
use serde_json::{Map, Value};

use super::ApiError;
use crate::web_push::payload::js_length;

/// The raw body, or 413 past the route's limit.
pub fn body(body: Result<Bytes, BytesRejection>) -> Result<Bytes, ApiError> {
    body.map_err(|rejection| {
        if rejection.status() == StatusCode::PAYLOAD_TOO_LARGE {
            ApiError::new(StatusCode::PAYLOAD_TOO_LARGE, "request entity too large")
        } else {
            ApiError::new(StatusCode::BAD_REQUEST, rejection.body_text())
        }
    })
}

/// The JSON object a request carries. A request that isn't `application/json` has an empty body, as Express
/// leaves it unparsed.
pub fn json_object(headers: &HeaderMap, body: &[u8]) -> Result<Map<String, Value>, ApiError> {
    let is_json = headers
        .get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(';').next())
        .is_some_and(|essence| essence.trim().eq_ignore_ascii_case("application/json"));
    if !is_json || body.is_empty() {
        return Ok(Map::new());
    }
    match serde_json::from_slice::<Value>(body) {
        Ok(Value::Object(map)) => Ok(map),
        Ok(Value::Array(_)) => Err(ApiError::validation(vec!["body must be an object".to_owned()])),
        Ok(_) | Err(_) => Err(ApiError::new(StatusCode::BAD_REQUEST, "Unexpected token in JSON")),
    }
}

/// Collects class-validator style messages for one DTO.
pub struct Validator<'a> {
    object: &'a Map<String, Value>,
    allowed: Vec<&'static str>,
    messages: Vec<String>,
}

impl<'a> Validator<'a> {
    pub fn new(object: &'a Map<String, Value>) -> Self {
        Self { object, allowed: Vec::new(), messages: Vec::new() }
    }

    fn value(&mut self, key: &'static str) -> Option<&'a Value> {
        self.allowed.push(key);
        self.object.get(key)
    }

    /// A required string that `accept` approves, reported with `message`.
    pub fn string(&mut self, key: &'static str, accept: impl Fn(&str) -> bool, message: &str) -> Option<&'a str> {
        match self.value(key) {
            Some(Value::String(value)) if accept(value) => Some(value),
            _ => {
                self.messages.push(format!("{key} {message}"));
                None
            }
        }
    }

    /// An optional string of `minimum..=maximum` characters; `null` counts as absent.
    pub fn optional_string(&mut self, key: &'static str, minimum: usize, maximum: usize) -> Option<&'a str> {
        match self.value(key) {
            None | Some(Value::Null) => None,
            Some(Value::String(value)) => {
                let length = js_length(value);
                if length > maximum {
                    self.messages.push(format!("{key} must be shorter than or equal to {maximum} characters"));
                } else if length < minimum {
                    self.messages.push(format!("{key} must be longer than or equal to {minimum} characters"));
                } else {
                    return Some(value);
                }
                None
            }
            Some(_) => {
                self.messages.push(format!("{key} must be a string"));
                None
            }
        }
    }

    /// Fails with every message, unknown properties included.
    pub fn finish(mut self) -> Result<(), ApiError> {
        for key in self.object.keys() {
            if !self.allowed.contains(&key.as_str()) {
                self.messages.push(format!("property {key} should not exist"));
            }
        }
        if self.messages.is_empty() { Ok(()) } else { Err(ApiError::validation(self.messages)) }
    }
}

pub fn is_apns_token(value: &str) -> bool {
    (64..=200).contains(&value.len()) && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

pub fn has_length(minimum: usize, maximum: usize) -> impl Fn(&str) -> bool {
    move |value| (minimum..=maximum).contains(&js_length(value))
}

/// validator.js `isBase64`: standard alphabet, a multiple of four characters, padding only at the end.
pub fn is_base64(value: &str) -> bool {
    if !value.len().is_multiple_of(4)
        || !value.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'+' || byte == b'/' || byte == b'=')
    {
        return false;
    }
    match value.find('=') {
        None => true,
        Some(index) => index == value.len() - 1 || (index == value.len() - 2 && value.ends_with('=')),
    }
}

/// An `Idempotency-Key` must be a UUID.
pub fn is_idempotency_key(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 36
        && bytes.iter().enumerate().all(|(index, byte)| match index {
            8 | 13 | 18 | 23 => *byte == b'-',
            14 => (b'1'..=b'8').contains(byte),
            19 => matches!(byte.to_ascii_lowercase(), b'8' | b'9' | b'a' | b'b'),
            _ => byte.is_ascii_hexdigit(),
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checks_base64_like_validator_js() {
        assert!(is_base64("AAAA"));
        assert!(is_base64("AAA="));
        assert!(is_base64("AA=="));
        assert!(!is_base64("A==="));
        assert!(!is_base64("AAA"));
        assert!(!is_base64("AA-_"));
    }

    #[test]
    fn checks_idempotency_keys() {
        assert!(is_idempotency_key("123e4567-e89b-42d3-a456-426614174000"));
        assert!(is_idempotency_key("123E4567-E89B-42D3-B456-426614174000"));
        assert!(!is_idempotency_key("123e4567-e89b-02d3-a456-426614174000"));
        assert!(!is_idempotency_key("123e4567-e89b-42d3-c456-426614174000"));
        assert!(!is_idempotency_key("not-a-key"));
    }
}
