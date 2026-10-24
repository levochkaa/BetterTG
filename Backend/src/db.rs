//! PostgreSQL access. The schema is the one the NestJS backend created, so existing databases keep working.

use sqlx::postgres::{PgPool, PgPoolOptions};
use sqlx::{FromRow, Postgres, Transaction};
use time::OffsetDateTime;
use uuid::Uuid;

pub mod migrations;

pub fn connect(database_url: &str) -> anyhow::Result<PgPool> {
    Ok(PgPoolOptions::new()
        .max_connections(10)
        .acquire_timeout(std::time::Duration::from_secs(5))
        .connect_lazy(database_url)?)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ApnsEnvironment {
    Sandbox,
    Production,
}

impl ApnsEnvironment {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Sandbox => "sandbox",
            Self::Production => "production",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "sandbox" => Some(Self::Sandbox),
            "production" => Some(Self::Production),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, FromRow)]
pub struct Installation {
    pub id: Uuid,
    pub management_secret_hash: String,
    pub apns_token_encrypted: String,
    pub apns_environment: String,
    pub bundle_id: String,
    pub app_attest_key_id: Option<String>,
    pub app_version: Option<String>,
    pub os_version: Option<String>,
    pub status: String,
    pub last_seen_at: OffsetDateTime,
}

impl Installation {
    pub fn is_active(&self) -> bool {
        self.status == "active"
    }

    pub fn environment(&self) -> ApnsEnvironment {
        ApnsEnvironment::parse(&self.apns_environment).unwrap_or(ApnsEnvironment::Production)
    }
}

pub struct NewInstallation<'a> {
    pub id: Uuid,
    pub management_secret_hash: &'a str,
    pub apns_token_encrypted: &'a str,
    pub apns_environment: ApnsEnvironment,
    pub bundle_id: &'a str,
    pub app_attest_key_id: Option<&'a str>,
    pub app_version: Option<&'a str>,
    pub os_version: Option<&'a str>,
}

/// A subscription with the status of its installation.
#[derive(Clone, Debug, FromRow)]
pub struct Subscription {
    pub id: Uuid,
    pub installation_id: Uuid,
    pub p256dh_private_key_encrypted: String,
    pub auth_secret_encrypted: String,
    pub installation_status: String,
}

pub struct NewSubscription<'a> {
    pub id: Uuid,
    pub installation_id: Uuid,
    pub endpoint_token_hash: &'a str,
    pub p256dh_public_key: &'a str,
    pub p256dh_private_key_encrypted: &'a str,
    pub auth_secret_encrypted: &'a str,
}

#[derive(Clone, Debug, FromRow)]
pub struct AppAttestKey {
    pub key_id: String,
    pub public_key_pem: String,
    pub sign_count: i32,
}

const INSTALLATION_COLUMNS: &str = "id, management_secret_hash, apns_token_encrypted, apns_environment, bundle_id, \
     app_attest_key_id, app_version, os_version, status, last_seen_at";

const SUBSCRIPTION_SELECT: &str = "SELECT s.id, s.installation_id, s.p256dh_private_key_encrypted, \
     s.auth_secret_encrypted, i.status AS installation_status \
     FROM telegram_push_subscriptions s JOIN installations i ON i.id = s.installation_id";

pub async fn insert_installation(pool: &PgPool, installation: &NewInstallation<'_>) -> sqlx::Result<()> {
    sqlx::query(
        "INSERT INTO installations (id, management_secret_hash, apns_token_encrypted, apns_environment, bundle_id, \
         app_attest_key_id, app_version, os_version, status, last_seen_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', now())",
    )
    .bind(installation.id)
    .bind(installation.management_secret_hash)
    .bind(installation.apns_token_encrypted)
    .bind(installation.apns_environment.as_str())
    .bind(installation.bundle_id)
    .bind(installation.app_attest_key_id)
    .bind(installation.app_version)
    .bind(installation.os_version)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn find_installation(pool: &PgPool, id: Uuid) -> sqlx::Result<Option<Installation>> {
    sqlx::query_as(&format!("SELECT {INSTALLATION_COLUMNS} FROM installations WHERE id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

/// Stores a fresh APNs token and reactivates the installation; absent versions keep their previous values.
pub async fn update_apns_token(
    pool: &PgPool,
    id: Uuid,
    apns_token_encrypted: &str,
    environment: ApnsEnvironment,
    app_version: Option<&str>,
    os_version: Option<&str>,
) -> sqlx::Result<()> {
    sqlx::query(
        "UPDATE installations SET apns_token_encrypted = $2, apns_environment = $3, \
         app_version = COALESCE($4, app_version), os_version = COALESCE($5, os_version), status = 'active', \
         last_seen_at = now(), updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(apns_token_encrypted)
    .bind(environment.as_str())
    .bind(app_version)
    .bind(os_version)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn disable_installation(pool: &PgPool, id: Uuid) -> sqlx::Result<()> {
    sqlx::query("UPDATE installations SET status = 'disabled', updated_at = now() WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

/// Deletes the installation, its subscription by cascade, and its App Attest key once no installation uses it.
/// Returns false when there was no such installation.
pub async fn delete_installation(pool: &PgPool, id: Uuid) -> sqlx::Result<bool> {
    let mut transaction = pool.begin().await?;
    let key_id: Option<Option<String>> =
        sqlx::query_scalar("SELECT app_attest_key_id FROM installations WHERE id = $1 FOR UPDATE")
            .bind(id)
            .fetch_optional(&mut *transaction)
            .await?;
    let Some(key_id) = key_id else { return Ok(false) };
    sqlx::query("DELETE FROM installations WHERE id = $1").bind(id).execute(&mut *transaction).await?;
    if let Some(key_id) = key_id {
        let remaining: i64 = sqlx::query_scalar("SELECT count(*) FROM installations WHERE app_attest_key_id = $1")
            .bind(&key_id)
            .fetch_one(&mut *transaction)
            .await?;
        if remaining == 0 {
            sqlx::query("DELETE FROM app_attest_keys WHERE key_id = $1")
                .bind(&key_id)
                .execute(&mut *transaction)
                .await?;
        }
    }
    transaction.commit().await?;
    Ok(true)
}

/// Replaces the installation's subscription, physically removing the previous key material.
pub async fn replace_subscription(pool: &PgPool, subscription: &NewSubscription<'_>) -> sqlx::Result<()> {
    let mut transaction = pool.begin().await?;
    sqlx::query("DELETE FROM telegram_push_subscriptions WHERE installation_id = $1")
        .bind(subscription.installation_id)
        .execute(&mut *transaction)
        .await?;
    sqlx::query(
        "INSERT INTO telegram_push_subscriptions (id, installation_id, endpoint_token_hash, p256dh_public_key, \
         p256dh_private_key_encrypted, auth_secret_encrypted, last_received_at) \
         VALUES ($1, $2, $3, $4, $5, $6, NULL)",
    )
    .bind(subscription.id)
    .bind(subscription.installation_id)
    .bind(subscription.endpoint_token_hash)
    .bind(subscription.p256dh_public_key)
    .bind(subscription.p256dh_private_key_encrypted)
    .bind(subscription.auth_secret_encrypted)
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await
}

pub async fn delete_subscription(pool: &PgPool, installation_id: Uuid, id: Uuid) -> sqlx::Result<bool> {
    let result = sqlx::query("DELETE FROM telegram_push_subscriptions WHERE id = $1 AND installation_id = $2")
        .bind(id)
        .bind(installation_id)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

pub async fn find_subscription_by_endpoint(
    pool: &PgPool,
    endpoint_token_hash: &str,
) -> sqlx::Result<Option<Subscription>> {
    sqlx::query_as(&format!("{SUBSCRIPTION_SELECT} WHERE s.endpoint_token_hash = $1"))
        .bind(endpoint_token_hash)
        .fetch_optional(pool)
        .await
}

pub async fn find_subscription(pool: &PgPool, id: Uuid) -> sqlx::Result<Option<Subscription>> {
    sqlx::query_as(&format!("{SUBSCRIPTION_SELECT} WHERE s.id = $1")).bind(id).fetch_optional(pool).await
}

pub async fn mark_subscription_received(pool: &PgPool, id: Uuid, received_at: OffsetDateTime) -> sqlx::Result<()> {
    sqlx::query("UPDATE telegram_push_subscriptions SET last_received_at = $2, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(received_at)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn find_app_attest_key(pool: &PgPool, key_id: &str) -> sqlx::Result<Option<AppAttestKey>> {
    sqlx::query_as("SELECT key_id, public_key_pem, sign_count FROM app_attest_keys WHERE key_id = $1")
        .bind(key_id)
        .fetch_optional(pool)
        .await
}

/// Registers an attested key, keeping the counter of a key attested before.
pub async fn upsert_app_attest_key(
    pool: &PgPool,
    key_id: &str,
    public_key_pem: &str,
    receipt_encrypted: &str,
) -> sqlx::Result<()> {
    sqlx::query(
        "INSERT INTO app_attest_keys (key_id, public_key_pem, receipt_encrypted, sign_count, revoked) \
         VALUES ($1, $2, $3, 0, false) \
         ON CONFLICT (key_id) DO UPDATE SET public_key_pem = EXCLUDED.public_key_pem, \
         receipt_encrypted = EXCLUDED.receipt_encrypted, revoked = false, updated_at = now()",
    )
    .bind(key_id)
    .bind(public_key_pem)
    .bind(receipt_encrypted)
    .execute(pool)
    .await?;
    Ok(())
}

/// Locks an unrevoked key for the rest of the transaction.
pub async fn lock_app_attest_key(
    transaction: &mut Transaction<'_, Postgres>,
    key_id: &str,
) -> sqlx::Result<Option<AppAttestKey>> {
    sqlx::query_as(
        "SELECT key_id, public_key_pem, sign_count FROM app_attest_keys WHERE key_id = $1 AND revoked = false \
         FOR UPDATE",
    )
    .bind(key_id)
    .fetch_optional(&mut **transaction)
    .await
}

pub async fn update_app_attest_sign_count(
    transaction: &mut Transaction<'_, Postgres>,
    key_id: &str,
    sign_count: i32,
) -> sqlx::Result<()> {
    sqlx::query("UPDATE app_attest_keys SET sign_count = $2, updated_at = now() WHERE key_id = $1")
        .bind(key_id)
        .bind(sign_count)
        .execute(&mut **transaction)
        .await?;
    Ok(())
}

pub async fn ping(pool: &PgPool) -> sqlx::Result<()> {
    sqlx::query("SELECT 1").execute(pool).await?;
    Ok(())
}
