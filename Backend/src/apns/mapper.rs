//! Turns a classified Telegram push into the smallest APNs payload that shows and routes it, within APNs' 4 KB.

use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use time::OffsetDateTime;

use super::{ApnsCommand, PushType};
use crate::security::SecretBox;
use crate::web_push::classifier::PushAction;
use crate::web_push::payload::{Identifier, TelegramPushPayload, js_length};

const APNS_PAYLOAD_LIMIT: usize = 4096;

#[derive(Debug, thiserror::Error)]
#[error("unable to fit APNs payload into 4096 bytes")]
pub struct PayloadTooLarge;

/// Shortens to `maximum` characters (code points), ending with "…" when anything was cut.
pub fn truncate(value: &str, maximum: usize) -> String {
    if value.chars().count() <= maximum {
        return value.to_owned();
    }
    if maximum <= 1 {
        return value.chars().take(maximum).collect();
    }
    let mut shortened: String = value.chars().take(maximum - 1).collect();
    shortened.push('…');
    shortened
}

/// The first UTF-16 units of `value`, never splitting a surrogate pair.
fn js_slice(value: &str, maximum: usize) -> String {
    let mut length = 0;
    value
        .chars()
        .take_while(|character| {
            length += character.len_utf16();
            length <= maximum
        })
        .collect()
}

/// Shrinks a text by 128 JavaScript characters, as the NestJS mapper did, and always by at least one character.
fn shrink(value: &str, step: usize) -> String {
    let shortened = truncate(value, js_length(value).saturating_sub(step));
    if shortened == value { truncate(value, value.chars().count().saturating_sub(step)) } else { shortened }
}

fn identifier(value: &Option<Identifier>) -> String {
    value.as_ref().map(ToString::to_string).unwrap_or_default()
}

fn truthy(value: &Option<Identifier>) -> bool {
    value.as_ref().is_some_and(Identifier::is_truthy)
}

struct Route {
    thread_id: String,
    data: Map<String, Value>,
}

enum Alert {
    Localized { loc_key: String, loc_args: Vec<String> },
    Preformatted { title: String, body: String },
}

impl Alert {
    fn json(&self) -> Value {
        match self {
            Self::Localized { loc_key, loc_args } => json!({ "loc-key": loc_key, "loc-args": loc_args }),
            Self::Preformatted { title, body } => json!({ "title": title, "body": body }),
        }
    }
}

pub struct ApnsPayloadMapper<'a> {
    pub secret_box: &'a SecretBox,
}

impl ApnsPayloadMapper<'_> {
    /// An alert or a background push, or None for pushes the relay drops.
    pub fn map(
        &self,
        action: PushAction,
        source: &TelegramPushPayload,
        delivery_seed: &str,
        now: OffsetDateTime,
        notification_payload_token: Option<&str>,
    ) -> Result<Option<ApnsCommand>, PayloadTooLarge> {
        match action {
            PushAction::Alert => self.alert(source, delivery_seed, now, notification_payload_token).map(Some),
            PushAction::Background => Ok(Some(self.background(source, delivery_seed, now))),
            _ => Ok(None),
        }
    }

    fn alert(
        &self,
        source: &TelegramPushPayload,
        delivery_seed: &str,
        now: OffsetDateTime,
        notification_payload_token: Option<&str>,
    ) -> Result<ApnsCommand, PayloadTooLarge> {
        let data = &source.data;
        let mut alert = match data.description.as_deref().filter(|description| !description.is_empty()) {
            Some(description) => Alert::Preformatted {
                title: truncate(data.title.as_deref().filter(|title| !title.is_empty()).unwrap_or("Telegram"), 512),
                body: truncate(description, 3072),
            },
            None => Alert::Localized {
                loc_key: data.loc_key.clone(),
                loc_args: data.loc_args.iter().map(|argument| truncate(argument, 2048)).collect(),
            },
        };
        let route = self.route(source);
        let mut tg = route.data;
        tg.insert("event".to_owned(), Value::String(data.loc_key.clone()));
        if let Some(token) = notification_payload_token {
            tg.insert("notification_payload_token".to_owned(), Value::String(token.to_owned()));
        }
        let silent = data.custom.silent == Some(true);
        let build = |alert: &Alert| {
            let mut aps = Map::new();
            aps.insert("alert".to_owned(), alert.json());
            if !silent {
                aps.insert("sound".to_owned(), Value::String("default".to_owned()));
            }
            aps.insert("thread-id".to_owned(), Value::String(route.thread_id.clone()));
            aps.insert("category".to_owned(), Value::String("TELEGRAM_MESSAGE".to_owned()));
            aps.insert("mutable-content".to_owned(), Value::from(1));
            json!({ "aps": aps, "tg": tg })
        };

        let mut payload = build(&alert);
        while payload.to_string().len() > APNS_PAYLOAD_LIMIT {
            match &mut alert {
                Alert::Preformatted { body, .. } if !body.is_empty() => *body = shrink(body, 128),
                Alert::Localized { loc_args, .. } if loc_args.iter().any(|argument| !argument.is_empty()) => {
                    let mut longest = 0;
                    for (index, argument) in loc_args.iter().enumerate() {
                        if js_length(argument) > js_length(&loc_args[longest]) {
                            longest = index;
                        }
                    }
                    loc_args[longest] = shrink(&loc_args[longest], 128);
                }
                Alert::Preformatted { title, .. } if !title.is_empty() => *title = shrink(title, 64),
                _ => return Err(PayloadTooLarge),
            }
            payload = build(&alert);
        }

        Ok(ApnsCommand {
            delivery_id: delivery_id(delivery_seed),
            push_type: PushType::Alert,
            priority: "10",
            expiration: (now.unix_timestamp() + 10 * 60).to_string(),
            collapse_id: None,
            payload,
        })
    }

    fn background(&self, source: &TelegramPushPayload, delivery_seed: &str, now: OffsetDateTime) -> ApnsCommand {
        let custom = &source.data.custom;
        let route = self.route(source);
        let mut tg = route.data;
        tg.insert("event".to_owned(), Value::String(source.data.loc_key.clone()));
        tg.insert("max_id".to_owned(), Value::String(identifier(&custom.max_id)));
        if let Some(messages) = &custom.messages {
            tg.insert("messages".to_owned(), Value::String(js_slice(messages, 512)));
        }
        ApnsCommand {
            delivery_id: delivery_id(delivery_seed),
            push_type: PushType::Background,
            priority: "5",
            expiration: (now.unix_timestamp() + 60).to_string(),
            collapse_id: Some(js_slice(&format!("state-{}", route.thread_id), 64)),
            payload: json!({ "aps": { "content-available": 1 }, "tg": tg }),
        }
    }

    /// Where the push belongs: the conversation, its author, and an opaque thread that groups the conversation's
    /// notifications.
    fn route(&self, source: &TelegramPushPayload) -> Route {
        let data = &source.data;
        let custom = &data.custom;
        let peer = if truthy(&custom.channel_id) {
            ("supergroup", identifier(&custom.channel_id))
        } else if truthy(&custom.chat_id) {
            ("basicGroup", identifier(&custom.chat_id))
        } else {
            ("private", identifier(&custom.from_id))
        };
        let account = identifier(&data.user_id);
        let sender = if truthy(&custom.chat_from_broadcast_id) {
            ("supergroup", identifier(&custom.chat_from_broadcast_id))
        } else if truthy(&custom.chat_from_group_id) {
            ("supergroup", identifier(&custom.chat_from_group_id))
        } else if truthy(&custom.chat_from_id) {
            ("private", identifier(&custom.chat_from_id))
        } else {
            peer.clone()
        };
        let thread_seed = format!("{account}:{}:{}", peer.0, peer.1);
        let sender_name =
            truncate(data.loc_args.first().map(String::as_str).or(data.title.as_deref()).unwrap_or_default(), 128);
        let conversation_title = if data.loc_key.starts_with("CHAT_") {
            data.loc_args.get(1)
        } else if data.loc_key.starts_with("CHANNEL_") {
            data.loc_args.first()
        } else {
            None
        };
        let entries = [
            ("account", account),
            ("peer_type", peer.0.to_owned()),
            ("peer_id", peer.1),
            ("sender_type", sender.0.to_owned()),
            ("sender_id", sender.1),
            ("sender_name", sender_name),
            ("conversation_title", truncate(conversation_title.map(String::as_str).unwrap_or_default(), 128)),
            ("message_id", identifier(&custom.msg_id)),
            ("top_message_id", identifier(&custom.top_msg_id)),
        ];
        Route {
            thread_id: self.secret_box.hash_management_token(&thread_seed)[..32].to_owned(),
            data: entries
                .into_iter()
                .filter(|(_, value)| !value.is_empty())
                .map(|(key, value)| (key.to_owned(), Value::String(value)))
                .collect(),
        }
    }
}

/// A UUID-shaped, version 5 identifier from SHA-256 of the seed, the same for every retry of a delivery.
pub fn delivery_id(seed: &str) -> String {
    let mut bytes: [u8; 16] = Sha256::digest(seed.as_bytes())[..16].try_into().expect("16 bytes");
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex = hex::encode(bytes);
    format!("{}-{}-{}-{}-{}", &hex[..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..])
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::security::tests::test_secret_box;
    use crate::web_push::payload::parse_telegram_push_payload;

    fn map(action: PushAction, value: Value, seed: &str, token: Option<&str>) -> Option<ApnsCommand> {
        let secret_box = test_secret_box();
        let payload = parse_telegram_push_payload(&value).unwrap();
        ApnsPayloadMapper { secret_box: &secret_box }
            .map(action, &payload, seed, OffsetDateTime::UNIX_EPOCH + time::Duration::days(20_688), token)
            .unwrap()
    }

    #[test]
    fn maps_a_message_to_a_localized_routable_alert() {
        let command = map(
            PushAction::Alert,
            json!({ "data": {
                "loc_key": "CHAT_MESSAGE_TEXT",
                "loc_args": ["Alice", "Family", "Hello"],
                "user_id": 42,
                "custom": { "chat_id": 7, "msg_id": 9 },
            }}),
            "delivery",
            Some("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        )
        .unwrap();
        assert_eq!(command.push_type, PushType::Alert);
        let aps = &command.payload["aps"];
        assert_eq!(aps["alert"], json!({ "loc-key": "CHAT_MESSAGE_TEXT", "loc-args": ["Alice", "Family", "Hello"] }));
        assert_eq!(aps["sound"], "default");
        assert_eq!(aps["mutable-content"], 1);
        assert_eq!(aps["thread-id"].as_str().unwrap().len(), 32);
        assert_eq!(
            command.payload["tg"],
            json!({
                "account": "42",
                "peer_type": "basicGroup",
                "peer_id": "7",
                "sender_type": "basicGroup",
                "sender_id": "7",
                "sender_name": "Alice",
                "conversation_title": "Family",
                "message_id": "9",
                "event": "CHAT_MESSAGE_TEXT",
                "notification_payload_token": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            })
        );
        assert_eq!(command.expiration, (1_787_443_200 + 600).to_string());
        assert_eq!(command.delivery_id.len(), 36);
        assert_eq!(&command.delivery_id[14..15], "5");
    }

    #[test]
    fn routes_a_group_author_separately_from_the_conversation() {
        let command = map(
            PushAction::Alert,
            json!({ "data": {
                "loc_key": "CHAT_MESSAGE_PHOTO",
                "loc_args": ["Alice", "Family"],
                "custom": { "chat_id": 7, "chat_from_id": 11, "msg_id": 9 },
            }}),
            "group-author",
            None,
        )
        .unwrap();
        let tg = &command.payload["tg"];
        assert_eq!(tg["peer_type"], "basicGroup");
        assert_eq!(tg["peer_id"], "7");
        assert_eq!(tg["sender_type"], "private");
        assert_eq!(tg["sender_id"], "11");
        assert_eq!(tg["conversation_title"], "Family");
        assert!(tg.get("account").is_none());
    }

    #[test]
    fn uses_the_title_and_description_preformatted_by_telegram_web_push() {
        let command = map(
            PushAction::Alert,
            json!({
                "loc_key": "MESSAGE_TEXT",
                "loc_args": ["Alice", "Hello"],
                "title": "Alice",
                "description": "Hello",
                "custom": { "from_id": 1, "msg_id": 2 },
            }),
            "preformatted",
            None,
        )
        .unwrap();
        assert_eq!(command.payload["aps"]["alert"], json!({ "title": "Alice", "body": "Hello" }));
    }

    #[test]
    fn omits_sound_for_silent_messages_and_trims_oversized_previews() {
        let command = map(
            PushAction::Alert,
            json!({ "data": {
                "loc_key": "MESSAGE_TEXT",
                "loc_args": ["Alice", "x".repeat(2000), "y".repeat(2000)],
                "custom": { "from_id": 1, "msg_id": 2, "silent": true },
            }}),
            "oversized",
            None,
        )
        .unwrap();
        assert!(command.payload["aps"].get("sound").is_none());
        assert!(command.payload.to_string().len() <= 4096);
        let arguments = command.payload["aps"]["alert"]["loc-args"].as_array().unwrap();
        assert!(arguments[1].as_str().unwrap().ends_with('…'));
    }

    #[test]
    fn trims_preformatted_bodies_made_of_astral_characters() {
        let command = map(
            PushAction::Alert,
            json!({ "loc_key": "MESSAGE_TEXT", "title": "Alice", "description": "😀".repeat(1500), "custom": { "from_id": 1 } }),
            "astral",
            None,
        )
        .unwrap();
        assert!(command.payload.to_string().len() <= 4096);
    }

    #[test]
    fn maps_read_state_to_a_coalesced_background_push() {
        let command = map(
            PushAction::Background,
            json!({ "data": { "loc_key": "READ_HISTORY", "custom": { "channel_id": 7, "max_id": 99 } } }),
            "read",
            None,
        )
        .unwrap();
        assert_eq!(command.push_type, PushType::Background);
        assert_eq!(command.priority, "5");
        assert_eq!(command.payload["aps"], json!({ "content-available": 1 }));
        assert_eq!(command.payload["tg"]["max_id"], "99");
        assert!(command.collapse_id.unwrap().len() <= 64);
    }

    #[test]
    fn does_not_create_commands_for_dropped_or_unknown_pushes() {
        let payload = json!({ "data": { "loc_key": "MESSAGE_MUTED", "custom": {} } });
        assert!(map(PushAction::Drop, payload.clone(), "drop", None).is_none());
        assert!(map(PushAction::Unknown, payload, "unknown", None).is_none());
    }

    #[test]
    fn derives_ids_like_the_node_backend() {
        // The NestJS mapper's deliveryId('delivery') and the thread of user 42's basic group 7.
        assert_eq!(delivery_id("delivery"), "b4af39d5-b65a-5484-9e88-5a9d65f0efe4");
        let command = map(
            PushAction::Alert,
            json!({ "data": { "loc_key": "CHAT_MESSAGE_TEXT", "user_id": 42, "custom": { "chat_id": 7 } } }),
            "thread",
            None,
        )
        .unwrap();
        assert_eq!(command.payload["aps"]["thread-id"], "d6102222ba68e25996509470ef08a58a");
    }
}
