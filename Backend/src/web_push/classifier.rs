//! Which Telegram pushes become alerts. Only exact keys from the reviewed catalog are shown; a new key stays
//! unknown, and hidden, until the catalog is regenerated and reviewed.

use std::collections::HashSet;
use std::sync::LazyLock;

use super::catalog::TELEGRAM_VISIBLE_PUSH_KEYS;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PushAction {
    Alert,
    Background,
    Drop,
    Call,
    Unknown,
}

impl PushAction {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Alert => "alert",
            Self::Background => "background",
            Self::Drop => "drop",
            Self::Call => "call",
            Self::Unknown => "unknown",
        }
    }
}

const BACKGROUND_KEYS: &[&str] = &["MESSAGE_DELETED", "READ_HISTORY", "READ_REACTION", "READ_STORIES", "STORY_DELETED"];
const DROPPED_KEYS: &[&str] = &["DC_UPDATE", "GEO_LIVE_PENDING", "MESSAGE_MUTED", "SESSION_REVOKE"];
const CALL_KEYS: &[&str] = &["PHONE_CALL_REQUEST"];

static VISIBLE_KEYS: LazyLock<HashSet<&'static str>> =
    LazyLock::new(|| TELEGRAM_VISIBLE_PUSH_KEYS.iter().map(|(key, _)| *key).collect());

pub fn classify(loc_key: &str) -> PushAction {
    if BACKGROUND_KEYS.contains(&loc_key) {
        PushAction::Background
    } else if DROPPED_KEYS.contains(&loc_key) {
        PushAction::Drop
    } else if CALL_KEYS.contains(&loc_key) {
        PushAction::Call
    } else if VISIBLE_KEYS.contains(loc_key) {
        PushAction::Alert
    } else {
        PushAction::Unknown
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_catalogued_visible_messages() {
        assert_eq!(classify("CHAT_MESSAGE_TEXT"), PushAction::Alert);
        assert_eq!(classify("CHANNEL_MESSAGE_PHOTO"), PushAction::Alert);
    }

    #[test]
    fn handles_service_and_call_pushes_before_visible_rules() {
        assert_eq!(classify("READ_HISTORY"), PushAction::Background);
        assert_eq!(classify("MESSAGE_MUTED"), PushAction::Drop);
        assert_eq!(classify("DC_UPDATE"), PushAction::Drop);
        assert_eq!(classify("PHONE_CALL_REQUEST"), PushAction::Call);
    }

    #[test]
    fn fails_closed_for_a_new_unreviewed_key() {
        assert_eq!(classify("MESSAGE_FUTURE_UNKNOWN"), PushAction::Unknown);
    }
}
