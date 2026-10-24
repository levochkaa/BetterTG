//! App Attest: one-time challenges, key registration from an attestation, and assertions over installation
//! requests. In bypass mode, allowed only outside production, nothing is checked.

pub mod verify;

use std::sync::Arc;

use sha2::{Digest, Sha256};
use sqlx::PgPool;

use crate::config::{AppAttestMode, Environment};
use crate::db;
use crate::redis_store::{RateLimitError, RedisStore};
use crate::security::{SecretBox, random_token, sha256_hex};
use verify::{AppAttestVerifier, same_public_key};

const CHALLENGE_TTL_SECONDS: u64 = 5 * 60;

#[derive(Debug, thiserror::Error)]
pub enum AppAttestError {
    #[error("{0}")]
    Unauthorized(&'static str),
    #[error("rate limit exceeded")]
    RateLimited,
    #[error(transparent)]
    Unavailable(#[from] anyhow::Error),
}

impl From<RateLimitError> for AppAttestError {
    fn from(error: RateLimitError) -> Self {
        match error {
            RateLimitError::Exceeded => Self::RateLimited,
            RateLimitError::Redis(error) => Self::Unavailable(error.into()),
        }
    }
}

impl From<redis::RedisError> for AppAttestError {
    fn from(error: redis::RedisError) -> Self {
        Self::Unavailable(error.into())
    }
}

impl From<sqlx::Error> for AppAttestError {
    fn from(error: sqlx::Error) -> Self {
        Self::Unavailable(error.into())
    }
}

pub struct Attestation<'a> {
    pub key_id: &'a str,
    pub challenge: &'a str,
    pub attestation: &'a [u8],
}

#[derive(Clone)]
pub struct AppAttestService {
    mode: AppAttestMode,
    verifier: Arc<AppAttestVerifier>,
    pool: PgPool,
    redis: RedisStore,
    secret_box: Arc<SecretBox>,
}

impl AppAttestService {
    pub fn new(environment: &Environment, pool: PgPool, redis: RedisStore, secret_box: Arc<SecretBox>) -> Self {
        let app_id = format!("{}.{}", environment.apple_team_id, environment.bundle_id);
        Self {
            mode: environment.app_attest_mode,
            verifier: Arc::new(AppAttestVerifier::new(app_id, environment.app_attest_allow_development)),
            pool,
            redis,
            secret_box,
        }
    }

    pub async fn issue_challenge(&self, ip_address: &str) -> Result<String, AppAttestError> {
        self.redis.enforce_rate_limit(&format!("app-attest:{ip_address}"), 30, 60).await?;
        let challenge = random_token();
        self.redis.set_ex(&challenge_key(&challenge), "1", CHALLENGE_TTL_SECONDS).await?;
        Ok(challenge)
    }

    pub async fn register_attestation(&self, attestation: &Attestation<'_>) -> Result<(), AppAttestError> {
        if self.mode == AppAttestMode::Bypass {
            return Ok(());
        }
        self.consume_challenge(attestation.challenge).await?;
        let verified = self
            .verifier
            .verify_attestation(attestation.key_id, attestation.challenge.as_bytes(), attestation.attestation)
            .map_err(|_| AppAttestError::Unauthorized("invalid app attestation"))?;
        if let Some(existing) = db::find_app_attest_key(&self.pool, attestation.key_id).await?
            && !same_public_key(&existing.public_key_pem, &verified.public_key_pem)
        {
            return Err(AppAttestError::Unauthorized("attestation key collision"));
        }
        let receipt = self.secret_box.encrypt(&verified.receipt, &format!("app-attest:{}:receipt", attestation.key_id));
        db::upsert_app_attest_key(&self.pool, attestation.key_id, &verified.public_key_pem, &receipt).await?;
        Ok(())
    }

    /// Checks the assertion over the exact request body and advances the key's counter. Returns the key ID to
    /// record on the installation, or None in bypass mode.
    pub async fn verify_request(
        &self,
        raw_body: &[u8],
        challenge: Option<&str>,
        key_id: Option<&str>,
        assertion_base64: Option<&str>,
    ) -> Result<Option<String>, AppAttestError> {
        if self.mode == AppAttestMode::Bypass {
            return Ok(None);
        }
        let (Some(challenge), Some(key_id), Some(assertion_base64)) = (challenge, key_id, assertion_base64) else {
            return Err(AppAttestError::Unauthorized("App Attest assertion is required"));
        };
        if raw_body.is_empty() {
            return Err(AppAttestError::Unauthorized("App Attest assertion is required"));
        }
        self.consume_challenge(challenge).await?;
        let assertion = crate::security::decode_base64_lenient(assertion_base64)
            .ok_or(AppAttestError::Unauthorized("invalid App Attest assertion"))?;
        let client_data_hash = Sha256::digest(raw_body);

        let mut transaction = self.pool.begin().await?;
        let key = db::lock_app_attest_key(&mut transaction, key_id)
            .await?
            .ok_or(AppAttestError::Unauthorized("unknown App Attest key"))?;
        let sign_count = self
            .verifier
            .verify_assertion(&client_data_hash, &key.public_key_pem, &assertion)
            .ok()
            .filter(|count| *count > key.sign_count)
            .ok_or(AppAttestError::Unauthorized("invalid App Attest assertion"))?;
        db::update_app_attest_sign_count(&mut transaction, key_id, sign_count).await?;
        transaction.commit().await?;
        Ok(Some(key_id.to_owned()))
    }

    async fn consume_challenge(&self, challenge: &str) -> Result<(), AppAttestError> {
        match self.redis.get_del(&challenge_key(challenge)).await?.as_deref() {
            Some("1") => Ok(()),
            _ => Err(AppAttestError::Unauthorized("invalid or expired challenge")),
        }
    }
}

fn challenge_key(challenge: &str) -> String {
    format!("app-attest:challenge:{}", sha256_hex(challenge.as_bytes()))
}
