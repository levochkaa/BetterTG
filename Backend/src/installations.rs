//! App installations: creation with an idempotency key, APNs token rotation, Web Push subscriptions and removal.

use std::sync::Arc;

use p256::SecretKey;
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::{self, ApnsEnvironment, Installation, NewInstallation, NewSubscription};
use crate::redis_store::RedisStore;
use crate::security::{SecretBox, base64url, hash_capability, random_bytes, random_token};
use crate::web_push::decryptor::{auth_secret_context, private_key_context};
use crate::web_push::ece::public_key_bytes;

const IDEMPOTENCY_TTL_SECONDS: u64 = 10 * 60;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct InstallationCreated {
    pub installation_id: Uuid,
    pub management_secret: String,
}

#[derive(Clone, Debug, Serialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TelegramSubscription {
    pub subscription_id: Uuid,
    pub endpoint: String,
    pub p256dh_base64url: String,
    pub auth_base64url: String,
}

pub struct NewInstallationRequest<'a> {
    pub apns_token: &'a str,
    pub apns_environment: ApnsEnvironment,
    pub app_version: Option<&'a str>,
    pub os_version: Option<&'a str>,
}

#[derive(Debug, thiserror::Error)]
pub enum InstallationError {
    #[error("installation creation is already running")]
    Conflict,
    #[error("not found")]
    NotFound,
    #[error(transparent)]
    Unavailable(#[from] anyhow::Error),
}

impl From<sqlx::Error> for InstallationError {
    fn from(error: sqlx::Error) -> Self {
        Self::Unavailable(error.into())
    }
}

impl From<redis::RedisError> for InstallationError {
    fn from(error: redis::RedisError) -> Self {
        Self::Unavailable(error.into())
    }
}

#[derive(Clone)]
pub struct InstallationsService {
    pub pool: PgPool,
    pub redis: RedisStore,
    pub secret_box: Arc<SecretBox>,
    pub bundle_id: String,
    pub public_base_url: String,
}

fn result_key(idempotency_key: &str) -> String {
    format!("installation:create:result:{idempotency_key}")
}

fn installation_idempotency_key(installation_id: &Uuid) -> String {
    format!("installation:create:idempotency:{installation_id}")
}

fn apns_token_context(installation_id: &Uuid) -> String {
    format!("installation:{installation_id}:apns-token")
}

impl InstallationsService {
    /// The response of an earlier creation with this key, kept encrypted for ten minutes.
    pub async fn cached_creation(
        &self,
        idempotency_key: &str,
    ) -> Result<Option<InstallationCreated>, InstallationError> {
        let Some(stored) = self.redis.get(&result_key(idempotency_key)).await? else { return Ok(None) };
        let plaintext = self
            .secret_box
            .decrypt(&stored, &format!("installation-idempotency:{idempotency_key}"))
            .map_err(anyhow::Error::from)?;
        Ok(Some(serde_json::from_slice(&plaintext).map_err(anyhow::Error::from)?))
    }

    pub async fn create(
        &self,
        request: &NewInstallationRequest<'_>,
        app_attest_key_id: Option<&str>,
        idempotency_key: &str,
    ) -> Result<InstallationCreated, InstallationError> {
        if let Some(cached) = self.cached_creation(idempotency_key).await? {
            return Ok(cached);
        }
        let lock_key = format!("installation:create:lock:{idempotency_key}");
        if !self.redis.set_nx_ex(&lock_key, "1", 15).await? {
            return Err(InstallationError::Conflict);
        }
        let result = self.create_locked(request, app_attest_key_id, idempotency_key).await;
        let _ = self.redis.del(&[lock_key]).await;
        result
    }

    async fn create_locked(
        &self,
        request: &NewInstallationRequest<'_>,
        app_attest_key_id: Option<&str>,
        idempotency_key: &str,
    ) -> Result<InstallationCreated, InstallationError> {
        if let Some(cached) = self.cached_creation(idempotency_key).await? {
            return Ok(cached);
        }
        let installation_id = Uuid::new_v4();
        let management_secret = random_token();
        db::insert_installation(
            &self.pool,
            &NewInstallation {
                id: installation_id,
                management_secret_hash: &self.secret_box.hash_management_token(&management_secret),
                apns_token_encrypted: &self
                    .secret_box
                    .encrypt(request.apns_token.to_ascii_lowercase(), &apns_token_context(&installation_id)),
                apns_environment: request.apns_environment,
                bundle_id: &self.bundle_id,
                app_attest_key_id,
                app_version: request.app_version,
                os_version: request.os_version,
            },
        )
        .await?;

        let response = InstallationCreated { installation_id, management_secret };
        let encrypted = self.secret_box.encrypt(
            serde_json::to_vec(&response).map_err(anyhow::Error::from)?,
            &format!("installation-idempotency:{idempotency_key}"),
        );
        self.redis.set_ex(&result_key(idempotency_key), &encrypted, IDEMPOTENCY_TTL_SECONDS).await?;
        self.redis
            .set_ex(&installation_idempotency_key(&installation_id), idempotency_key, IDEMPOTENCY_TTL_SECONDS)
            .await?;
        Ok(response)
    }

    pub async fn update_apns_token(
        &self,
        installation: &Installation,
        apns_token: &str,
        environment: ApnsEnvironment,
        app_version: Option<&str>,
        os_version: Option<&str>,
    ) -> Result<(), InstallationError> {
        let encrypted = self.secret_box.encrypt(apns_token.to_ascii_lowercase(), &apns_token_context(&installation.id));
        db::update_apns_token(&self.pool, installation.id, &encrypted, environment, app_version, os_version).await?;
        Ok(())
    }

    /// Issues a new Web Push endpoint and key pair, replacing the previous subscription.
    pub async fn rotate_subscription(
        &self,
        installation: &Installation,
    ) -> Result<TelegramSubscription, InstallationError> {
        let subscription_id = Uuid::new_v4();
        let endpoint_token = random_token();
        let private_key = SecretKey::random(&mut OsRng);
        let public_key = base64url::encode(public_key_bytes(&private_key));
        let auth_secret = random_bytes::<16>();
        db::replace_subscription(
            &self.pool,
            &NewSubscription {
                id: subscription_id,
                installation_id: installation.id,
                endpoint_token_hash: &hash_capability(&endpoint_token),
                p256dh_public_key: &public_key,
                p256dh_private_key_encrypted: &self
                    .secret_box
                    .encrypt(private_key.to_bytes(), &private_key_context(&subscription_id)),
                auth_secret_encrypted: &self.secret_box.encrypt(auth_secret, &auth_secret_context(&subscription_id)),
            },
        )
        .await?;
        Ok(TelegramSubscription {
            subscription_id,
            endpoint: format!("{}/webpush/v1/{endpoint_token}", self.public_base_url.trim_end_matches('/')),
            p256dh_base64url: public_key,
            auth_base64url: base64url::encode(auth_secret),
        })
    }

    pub async fn delete_subscription(
        &self,
        installation_id: Uuid,
        subscription_id: Uuid,
    ) -> Result<(), InstallationError> {
        if db::delete_subscription(&self.pool, installation_id, subscription_id).await? {
            Ok(())
        } else {
            Err(InstallationError::NotFound)
        }
    }

    pub async fn delete_installation(&self, installation_id: Uuid) -> Result<(), InstallationError> {
        if !db::delete_installation(&self.pool, installation_id).await? {
            return Err(InstallationError::NotFound);
        }
        let key = installation_idempotency_key(&installation_id);
        let mut keys = vec![key.clone()];
        if let Some(idempotency_key) = self.redis.get(&key).await? {
            keys.push(result_key(&idempotency_key));
        }
        self.redis.del(&keys).await?;
        Ok(())
    }

    /// The installation a bearer token belongs to; None for a malformed, unknown or wrong token.
    pub async fn authenticate(
        &self,
        installation_id: &str,
        authorization: Option<&str>,
    ) -> Result<Option<Installation>, InstallationError> {
        let Some(token) = authorization.and_then(|value| value.strip_prefix("Bearer ")) else { return Ok(None) };
        if token.len() < 40 || !token.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_') {
            return Ok(None);
        }
        let Ok(installation_id) = Uuid::parse_str(installation_id) else { return Ok(None) };
        let Some(installation) = db::find_installation(&self.pool, installation_id).await? else { return Ok(None) };
        let actual = self.secret_box.hash_management_token(token);
        Ok(crate::security::secure_hash_matches(&installation.management_secret_hash, &actual).then_some(installation))
    }
}
