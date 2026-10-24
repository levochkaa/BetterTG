//! The decrypted Telegram push: strictly bounded, with Telegram's `0`/`1`/boolean flags normalized to `"0"`/`"1"`.
//! Fields the relay doesn't know pass through for the Notification Service Extension.

use std::fmt;

use serde_json::{Map, Value};

#[derive(Debug, thiserror::Error)]
#[error("invalid Telegram push payload: {0}")]
pub struct PayloadError(String);

/// Telegram identifiers arrive as numbers or strings.
#[derive(Clone, Debug, PartialEq)]
pub enum Identifier {
    Text(String),
    Number(i64),
}

impl Identifier {
    /// JavaScript truthiness: `0` and `""` don't count.
    pub fn is_truthy(&self) -> bool {
        match self {
            Self::Text(text) => !text.is_empty(),
            Self::Number(number) => *number != 0,
        }
    }
}

impl fmt::Display for Identifier {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Text(text) => formatter.write_str(text),
            Self::Number(number) => write!(formatter, "{number}"),
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct Custom {
    pub msg_id: Option<Identifier>,
    pub channel_id: Option<Identifier>,
    pub chat_id: Option<Identifier>,
    pub from_id: Option<Identifier>,
    pub chat_from_broadcast_id: Option<Identifier>,
    pub chat_from_group_id: Option<Identifier>,
    pub chat_from_id: Option<Identifier>,
    pub top_msg_id: Option<Identifier>,
    pub silent: Option<bool>,
    pub mention: Option<bool>,
    pub max_id: Option<Identifier>,
    pub messages: Option<String>,
}

#[derive(Clone, Debug)]
pub struct PushData {
    pub loc_key: String,
    pub loc_args: Vec<String>,
    pub user_id: Option<Identifier>,
    pub sound: Option<String>,
    pub message: Option<String>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub custom: Custom,
}

#[derive(Clone, Debug)]
pub struct TelegramPushPayload {
    pub data: PushData,
    /// The normalized payload as `{"data": {...}, ...}`, unknown fields included.
    pub json: Value,
}

/// String length as JavaScript counts it, in UTF-16 code units.
pub fn js_length(value: &str) -> usize {
    value.encode_utf16().count()
}

const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;

fn identifier(value: &Value, field: &str) -> Result<Identifier, PayloadError> {
    match value {
        Value::String(text) if js_length(text) <= 32 => Ok(Identifier::Text(text.clone())),
        Value::Number(number) => {
            if let Some(integer) = number.as_i64() {
                if (integer as f64).abs() <= MAX_SAFE_INTEGER {
                    return Ok(Identifier::Number(integer));
                }
            } else if let Some(float) = number.as_f64()
                && float.fract() == 0.0
                && float.abs() <= MAX_SAFE_INTEGER
            {
                return Ok(Identifier::Number(float as i64));
            }
            Err(PayloadError(format!("{field} must be a safe integer")))
        }
        _ => Err(PayloadError(format!("{field} must be an identifier"))),
    }
}

fn identifier_value(identifier: &Identifier) -> Value {
    match identifier {
        Identifier::Text(text) => Value::String(text.clone()),
        Identifier::Number(number) => Value::from(*number),
    }
}

fn flag(value: &Value, field: &str) -> Result<bool, PayloadError> {
    match value {
        Value::Bool(flag) => Ok(*flag),
        Value::String(text) if text == "0" || text == "1" => Ok(text == "1"),
        Value::Number(number) if number.as_f64() == Some(0.0) || number.as_f64() == Some(1.0) => {
            Ok(number.as_f64() == Some(1.0))
        }
        _ => Err(PayloadError(format!("{field} must be a Telegram flag"))),
    }
}

fn bounded_string(value: &Value, field: &str, maximum: usize) -> Result<String, PayloadError> {
    match value {
        Value::String(text) if js_length(text) <= maximum => Ok(text.clone()),
        _ => Err(PayloadError(format!("{field} must be a string of at most {maximum} characters"))),
    }
}

/// Reads known keys in schema order, then appends unknown ones, as zod's `passthrough()` does.
struct ObjectReader<'a> {
    source: &'a Map<String, Value>,
    output: Map<String, Value>,
    known: Vec<&'static str>,
}

impl<'a> ObjectReader<'a> {
    fn new(source: &'a Map<String, Value>) -> Self {
        Self { source, output: Map::new(), known: Vec::new() }
    }

    /// The value of a present key; `null` counts as present and fails validation, as in zod.
    fn take(&mut self, key: &'static str) -> Option<&'a Value> {
        self.known.push(key);
        self.source.get(key)
    }

    fn put(&mut self, key: &'static str, value: Value) {
        self.output.insert(key.to_owned(), value);
    }

    fn finish(mut self) -> Map<String, Value> {
        for (key, value) in self.source {
            if !self.known.contains(&key.as_str()) {
                self.output.insert(key.clone(), value.clone());
            }
        }
        self.output
    }
}

fn parse_custom(value: Option<&Value>) -> Result<(Custom, Value), PayloadError> {
    let empty = Map::new();
    let source = match value {
        None => &empty,
        Some(Value::Object(map)) => map,
        Some(_) => return Err(PayloadError("custom must be an object".to_owned())),
    };
    let mut reader = ObjectReader::new(source);
    let mut custom = Custom::default();
    type Slot = fn(&mut Custom) -> &mut Option<Identifier>;
    let identifiers: [(&'static str, Slot); 8] = [
        ("msg_id", |custom| &mut custom.msg_id),
        ("channel_id", |custom| &mut custom.channel_id),
        ("chat_id", |custom| &mut custom.chat_id),
        ("from_id", |custom| &mut custom.from_id),
        ("chat_from_broadcast_id", |custom| &mut custom.chat_from_broadcast_id),
        ("chat_from_group_id", |custom| &mut custom.chat_from_group_id),
        ("chat_from_id", |custom| &mut custom.chat_from_id),
        ("top_msg_id", |custom| &mut custom.top_msg_id),
    ];
    for (key, slot) in identifiers {
        if let Some(value) = reader.take(key) {
            let parsed = identifier(value, key)?;
            reader.put(key, identifier_value(&parsed));
            *slot(&mut custom) = Some(parsed);
        }
    }
    for (key, slot) in [("silent", &mut custom.silent), ("mention", &mut custom.mention)] {
        if let Some(value) = reader.take(key) {
            let parsed = flag(value, key)?;
            reader.put(key, Value::String(if parsed { "1" } else { "0" }.to_owned()));
            *slot = Some(parsed);
        }
    }
    if let Some(value) = reader.take("max_id") {
        let parsed = identifier(value, "max_id")?;
        reader.put("max_id", identifier_value(&parsed));
        custom.max_id = Some(parsed);
    }
    if let Some(value) = reader.take("messages") {
        let parsed = bounded_string(value, "messages", 1024)?;
        reader.put("messages", Value::String(parsed.clone()));
        custom.messages = Some(parsed);
    }
    Ok((custom, Value::Object(reader.finish())))
}

fn parse_data(value: &Value) -> Result<(PushData, Value), PayloadError> {
    let Value::Object(source) = value else { return Err(PayloadError("data must be an object".to_owned())) };
    let mut reader = ObjectReader::new(source);

    let loc_key = match reader.take("loc_key") {
        Some(Value::String(key))
            if !key.is_empty() && key.bytes().all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_') =>
        {
            key.clone()
        }
        _ => return Err(PayloadError("loc_key must match /^[A-Z0-9_]+$/".to_owned())),
    };
    reader.put("loc_key", Value::String(loc_key.clone()));

    let loc_args = match reader.take("loc_args") {
        None => Vec::new(),
        Some(Value::Array(items)) if items.len() <= 12 => {
            items.iter().map(|item| bounded_string(item, "loc_args", 2048)).collect::<Result<Vec<_>, _>>()?
        }
        Some(_) => return Err(PayloadError("loc_args must hold at most 12 strings".to_owned())),
    };
    reader.put("loc_args", Value::Array(loc_args.iter().cloned().map(Value::String).collect()));

    let user_id = match reader.take("user_id") {
        Some(value) => {
            let parsed = identifier(value, "user_id")?;
            reader.put("user_id", identifier_value(&parsed));
            Some(parsed)
        }
        None => None,
    };
    let mut strings =
        [("sound", 128, None), ("message", 3072, None), ("title", 512, None), ("description", 3072, None)];
    for (key, maximum, slot) in &mut strings {
        if let Some(value) = reader.take(key) {
            let parsed = bounded_string(value, key, *maximum)?;
            reader.put(key, Value::String(parsed.clone()));
            *slot = Some(parsed);
        }
    }
    let [(_, _, sound), (_, _, message), (_, _, title), (_, _, description)] = strings;

    let (custom, custom_json) = parse_custom(reader.take("custom"))?;
    reader.put("custom", custom_json);

    let data = PushData { loc_key, loc_args, user_id, sound, message, title, description, custom };
    Ok((data, Value::Object(reader.finish())))
}

/// Accepts `{"data": {...}}` and the flat payload Telegram Web Push sends, normalizing both to the first.
pub fn parse_telegram_push_payload(value: &Value) -> Result<TelegramPushPayload, PayloadError> {
    if let Value::Object(source) = value
        && source.contains_key("data")
    {
        let mut reader = ObjectReader::new(source);
        let (data, data_json) = parse_data(reader.take("data").expect("checked above"))?;
        reader.put("data", data_json);
        return Ok(TelegramPushPayload { data, json: Value::Object(reader.finish()) });
    }
    let (data, data_json) = parse_data(value)?;
    let mut json = Map::new();
    json.insert("data".to_owned(), data_json);
    Ok(TelegramPushPayload { data, json: Value::Object(json) })
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn accepts_a_bounded_telegram_message_payload() {
        let payload = parse_telegram_push_payload(&json!({
            "data": {
                "loc_key": "CHAT_MESSAGE_TEXT",
                "loc_args": ["Alice", "Family", "Hello"],
                "user_id": 42,
                "custom": { "chat_id": 5, "msg_id": 9 },
            },
        }))
        .unwrap();
        assert_eq!(payload.data.custom.msg_id, Some(Identifier::Number(9)));
        assert_eq!(payload.data.user_id.unwrap().to_string(), "42");
    }

    #[test]
    fn normalizes_the_flat_payload_sent_by_telegram_web_push() {
        let payload = parse_telegram_push_payload(&json!({
            "loc_key": "MESSAGE_TEXT",
            "loc_args": ["Alice", "Hello"],
            "user_id": 42,
            "custom": { "from_id": "5", "msg_id": "9", "silent": 1 },
            "mute": "0",
            "badge": "1",
            "title": "Alice",
            "description": "Hello",
        }))
        .unwrap();
        assert_eq!(payload.data.loc_key, "MESSAGE_TEXT");
        assert_eq!(payload.json["data"]["custom"], json!({ "from_id": "5", "msg_id": "9", "silent": "1" }));
        assert_eq!(payload.data.title.as_deref(), Some("Alice"));
        assert_eq!(payload.json["data"]["mute"], json!("0"));
        assert_eq!(
            serde_json::to_string(&payload.json).unwrap(),
            r#"{"data":{"loc_key":"MESSAGE_TEXT","loc_args":["Alice","Hello"],"user_id":42,"title":"Alice","description":"Hello","custom":{"msg_id":"9","from_id":"5","silent":"1"},"mute":"0","badge":"1"}}"#
        );
    }

    #[test]
    fn defaults_missing_arguments_and_custom_fields() {
        let payload = parse_telegram_push_payload(&json!({ "data": { "loc_key": "READ_HISTORY" } })).unwrap();
        assert!(payload.data.loc_args.is_empty());
        assert_eq!(payload.json, json!({ "data": { "loc_key": "READ_HISTORY", "loc_args": [], "custom": {} } }));
    }

    #[test]
    fn rejects_malformed_keys_and_oversized_arguments() {
        assert!(
            parse_telegram_push_payload(&json!({ "data": { "loc_key": "message-text", "loc_args": [] } })).is_err()
        );
        assert!(
            parse_telegram_push_payload(
                &json!({ "data": { "loc_key": "MESSAGE_TEXT", "loc_args": ["x".repeat(2049)] } })
            )
            .is_err()
        );
        assert!(
            parse_telegram_push_payload(&json!({ "data": { "loc_key": "A", "loc_args": vec!["x"; 13] } })).is_err()
        );
        assert!(
            parse_telegram_push_payload(
                &json!({ "data": { "loc_key": "A", "custom": { "msg_id": 9_007_199_254_740_992u64 } } })
            )
            .is_err()
        );
        assert!(
            parse_telegram_push_payload(&json!({ "data": { "loc_key": "A", "custom": { "silent": "2" } } })).is_err()
        );
        assert!(parse_telegram_push_payload(&json!({ "data": { "loc_key": "A", "user_id": null } })).is_err());
        assert!(parse_telegram_push_payload(&json!(["MESSAGE_TEXT"])).is_err());
    }
}
