//! One JSON object per line on stdout. Keys that may carry secrets or message content are redacted before
//! anything is written, wherever they appear.

use std::fmt::Write as _;
use std::io::Write as _;

use serde_json::{Map, Value};
use time::OffsetDateTime;
use time::format_description::BorrowedFormatItem;
use time::macros::format_description;
use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::Layer;
use tracing_subscriber::layer::Context;

use crate::config::LogLevel;

const REDACTED: &str = "[REDACTED]";

/// `Date.toISOString()`: UTC with exactly three fractional digits.
const TIMESTAMP: &[BorrowedFormatItem<'_>] =
    format_description!("[year]-[month]-[day]T[hour]:[minute]:[second].[subsecond digits:3]Z");

pub fn iso_timestamp(time: OffsetDateTime) -> String {
    time.to_offset(time::UtcOffset::UTC).format(TIMESTAMP).unwrap_or_default()
}

/// Matches `/(token|secret|password|authorization|payload|loc_?args|ciphertext|private_?key)/i`.
pub fn is_secret_key(key: &str) -> bool {
    let key = key.to_ascii_lowercase();
    ["token", "secret", "password", "authorization", "payload", "locargs", "loc_args", "ciphertext"]
        .iter()
        .any(|needle| key.contains(needle))
        || key.contains("privatekey")
        || key.contains("private_key")
}

/// Replaces the value of every secret-looking key, recursively.
pub fn redact(value: Value) -> Value {
    match value {
        Value::Object(map) => Value::Object(
            map.into_iter()
                .map(|(key, child)| {
                    let child = if is_secret_key(&key) { Value::String(REDACTED.to_owned()) } else { redact(child) };
                    (key, child)
                })
                .collect(),
        ),
        Value::Array(items) => Value::Array(items.into_iter().map(redact).collect()),
        other => other,
    }
}

pub fn level_filter(level: LogLevel) -> tracing::level_filters::LevelFilter {
    use tracing::level_filters::LevelFilter;
    match level {
        LogLevel::Debug => LevelFilter::DEBUG,
        LogLevel::Info => LevelFilter::INFO,
        LogLevel::Warn => LevelFilter::WARN,
        LogLevel::Error => LevelFilter::ERROR,
    }
}

/// Writes events as `{"timestamp", "level", ...fields}`.
pub struct JsonLogLayer;

#[derive(Default)]
struct FieldVisitor(Map<String, Value>);

impl Visit for FieldVisitor {
    fn record_str(&mut self, field: &Field, value: &str) {
        self.0.insert(field.name().to_owned(), Value::String(value.to_owned()));
    }

    fn record_bool(&mut self, field: &Field, value: bool) {
        self.0.insert(field.name().to_owned(), Value::Bool(value));
    }

    fn record_i64(&mut self, field: &Field, value: i64) {
        self.0.insert(field.name().to_owned(), Value::from(value));
    }

    fn record_u64(&mut self, field: &Field, value: u64) {
        self.0.insert(field.name().to_owned(), Value::from(value));
    }

    fn record_f64(&mut self, field: &Field, value: f64) {
        self.0.insert(field.name().to_owned(), Value::from(value));
    }

    fn record_error(&mut self, field: &Field, value: &(dyn std::error::Error + 'static)) {
        let mut message = value.to_string();
        let mut source = value.source();
        while let Some(cause) = source {
            let _ = write!(message, ": {cause}");
            source = cause.source();
        }
        self.0.insert(field.name().to_owned(), Value::String(message));
    }

    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        self.0.insert(field.name().to_owned(), Value::String(format!("{value:?}")));
    }
}

fn level_name(level: &Level) -> &'static str {
    match *level {
        Level::ERROR => "error",
        Level::WARN => "warn",
        Level::INFO => "info",
        _ => "debug",
    }
}

impl<S: Subscriber> Layer<S> for JsonLogLayer {
    fn on_event(&self, event: &Event<'_>, _context: Context<'_, S>) {
        let mut visitor = FieldVisitor::default();
        event.record(&mut visitor);
        let mut entry = Map::new();
        let timestamp = iso_timestamp(OffsetDateTime::now_utc());
        entry.insert("timestamp".to_owned(), Value::String(timestamp));
        entry.insert("level".to_owned(), Value::String(level_name(event.metadata().level()).to_owned()));
        if let Value::Object(fields) = redact(Value::Object(visitor.0)) {
            entry.extend(fields);
        }
        let mut line = serde_json::to_vec(&Value::Object(entry)).unwrap_or_default();
        line.push(b'\n');
        let _ = std::io::stdout().lock().write_all(&line);
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn redacts_secrets_recursively_without_hiding_safe_metadata() {
        assert_eq!(
            redact(json!({
                "event": "delivery.failed",
                "authorization": "Bearer secret",
                "nested": { "apnsToken": "token", "status": 410 },
                "loc_args": ["private text"],
                "privateKey": "key",
            })),
            json!({
                "event": "delivery.failed",
                "authorization": "[REDACTED]",
                "nested": { "apnsToken": "[REDACTED]", "status": 410 },
                "loc_args": "[REDACTED]",
                "privateKey": "[REDACTED]",
            })
        );
    }

    #[test]
    fn keeps_routing_metadata_keys() {
        for key in ["subscriptionId", "locKey", "contentEncoding", "bodyBytes", "pushType", "reason"] {
            assert!(!is_secret_key(key), "{key}");
        }
        for key in ["managementSecret", "notification_payload_token", "locArgs", "ciphertextBase64"] {
            assert!(is_secret_key(key), "{key}");
        }
    }
}
