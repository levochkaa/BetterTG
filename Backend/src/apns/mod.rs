//! Apple Push Notification service: the payloads the relay sends and the HTTP/2 provider client.

pub mod client;
pub mod mapper;

use serde_json::Value;

use crate::db::ApnsEnvironment;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PushType {
    Alert,
    Background,
}

impl PushType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Alert => "alert",
            Self::Background => "background",
        }
    }
}

/// What to send, before the device and topic are known.
#[derive(Clone, Debug)]
pub struct ApnsCommand {
    pub delivery_id: String,
    pub push_type: PushType,
    pub priority: &'static str,
    pub expiration: String,
    pub collapse_id: Option<String>,
    pub payload: Value,
}

#[derive(Clone, Debug)]
pub struct ApnsRequest {
    pub device_token: String,
    pub environment: ApnsEnvironment,
    pub topic: String,
    pub command: ApnsCommand,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ApnsResult {
    Success,
    Retryable { status: Option<u16>, reason: Option<String> },
    InvalidToken { status: u16, reason: String },
    Permanent { status: Option<u16>, reason: Option<String> },
}

impl ApnsResult {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Success => "success",
            Self::Retryable { .. } => "retryable",
            Self::InvalidToken { .. } => "invalid-token",
            Self::Permanent { .. } => "permanent",
        }
    }

    pub fn reason(&self) -> Option<&str> {
        match self {
            Self::Success => None,
            Self::Retryable { reason, .. } | Self::Permanent { reason, .. } => reason.as_deref(),
            Self::InvalidToken { reason, .. } => Some(reason),
        }
    }
}
