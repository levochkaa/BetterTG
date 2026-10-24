//! Schema migrations, recorded in `schema_migrations`. A database the NestJS backend migrated with TypeORM is
//! adopted as is: a migration listed in TypeORM's `migrations` table counts as applied.

use sqlx::PgPool;

pub struct Migration {
    pub version: i64,
    pub name: &'static str,
    pub up: &'static [&'static str],
    pub down: &'static [&'static str],
}

pub const MIGRATIONS: &[Migration] = &[Migration {
    version: 1_787_500_000_000,
    name: "CreatePushRelaySchema1787500000000",
    up: &[
        r#"CREATE TABLE "app_attest_keys" (
            "key_id" varchar(255) NOT NULL,
            "public_key_pem" text NOT NULL,
            "receipt_encrypted" text NOT NULL,
            "sign_count" integer NOT NULL DEFAULT 0,
            "revoked" boolean NOT NULL DEFAULT false,
            "created_at" timestamptz NOT NULL DEFAULT now(),
            "updated_at" timestamptz NOT NULL DEFAULT now(),
            CONSTRAINT "PK_app_attest_keys" PRIMARY KEY ("key_id")
        )"#,
        r#"CREATE TABLE "installations" (
            "id" uuid NOT NULL,
            "management_secret_hash" char(64) NOT NULL,
            "apns_token_encrypted" text NOT NULL,
            "apns_environment" varchar(16) NOT NULL,
            "bundle_id" varchar(255) NOT NULL,
            "app_attest_key_id" varchar(255),
            "app_version" varchar(64),
            "os_version" varchar(64),
            "status" varchar(16) NOT NULL DEFAULT 'active',
            "last_seen_at" timestamptz NOT NULL,
            "created_at" timestamptz NOT NULL DEFAULT now(),
            "updated_at" timestamptz NOT NULL DEFAULT now(),
            CONSTRAINT "PK_installations" PRIMARY KEY ("id"),
            CONSTRAINT "CHK_installations_apns_environment"
                CHECK ("apns_environment" IN ('sandbox', 'production')),
            CONSTRAINT "CHK_installations_status"
                CHECK ("status" IN ('active', 'disabled')),
            CONSTRAINT "FK_installations_app_attest_key"
                FOREIGN KEY ("app_attest_key_id") REFERENCES "app_attest_keys"("key_id")
                ON DELETE SET NULL
        )"#,
        r#"CREATE INDEX "IDX_installations_status" ON "installations" ("status")"#,
        r#"CREATE TABLE "telegram_push_subscriptions" (
            "id" uuid NOT NULL,
            "endpoint_token_hash" char(64) NOT NULL,
            "p256dh_public_key" varchar(128) NOT NULL,
            "p256dh_private_key_encrypted" text NOT NULL,
            "auth_secret_encrypted" text NOT NULL,
            "last_received_at" timestamptz,
            "created_at" timestamptz NOT NULL DEFAULT now(),
            "updated_at" timestamptz NOT NULL DEFAULT now(),
            "installation_id" uuid NOT NULL,
            CONSTRAINT "PK_telegram_push_subscriptions" PRIMARY KEY ("id"),
            CONSTRAINT "UQ_telegram_push_subscriptions_endpoint" UNIQUE ("endpoint_token_hash"),
            CONSTRAINT "UQ_telegram_push_subscriptions_installation" UNIQUE ("installation_id"),
            CONSTRAINT "FK_telegram_push_subscriptions_installation"
                FOREIGN KEY ("installation_id") REFERENCES "installations"("id")
                ON DELETE CASCADE
        )"#,
    ],
    down: &[
        r#"DROP TABLE "telegram_push_subscriptions""#,
        r#"DROP INDEX "IDX_installations_status""#,
        r#"DROP TABLE "installations""#,
        r#"DROP TABLE "app_attest_keys""#,
    ],
}];

/// Serializes migration commands across processes.
const LOCK_KEY: i64 = 0x6265_7474_6572_7467;

async fn prepare(connection: &mut sqlx::PgConnection) -> sqlx::Result<()> {
    sqlx::query("SELECT pg_advisory_lock($1)").bind(LOCK_KEY).execute(&mut *connection).await?;
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS schema_migrations (version bigint PRIMARY KEY, name text NOT NULL, \
         applied_at timestamptz NOT NULL DEFAULT now())",
    )
    .execute(&mut *connection)
    .await?;
    let typeorm_table: Option<String> =
        sqlx::query_scalar("SELECT to_regclass('public.migrations')::text").fetch_one(&mut *connection).await?;
    if typeorm_table.is_some() {
        sqlx::query(
            "INSERT INTO schema_migrations (version, name) SELECT timestamp, name FROM migrations \
             ON CONFLICT (version) DO NOTHING",
        )
        .execute(&mut *connection)
        .await?;
    }
    Ok(())
}

async fn applied(connection: &mut sqlx::PgConnection) -> sqlx::Result<Vec<i64>> {
    sqlx::query_scalar("SELECT version FROM schema_migrations ORDER BY version").fetch_all(connection).await
}

async fn unlock(connection: &mut sqlx::PgConnection) {
    let _ = sqlx::query("SELECT pg_advisory_unlock($1)").bind(LOCK_KEY).execute(connection).await;
}

/// Applies every pending migration, each in its own transaction. Returns the names applied.
pub async fn run(pool: &PgPool) -> anyhow::Result<Vec<&'static str>> {
    let mut connection = pool.acquire().await?;
    prepare(&mut connection).await?;
    let result = async {
        let done = applied(&mut connection).await?;
        let mut names = Vec::new();
        for migration in MIGRATIONS.iter().filter(|migration| !done.contains(&migration.version)) {
            let mut transaction = sqlx::Connection::begin(&mut *connection).await?;
            for statement in migration.up {
                sqlx::query(statement).execute(&mut *transaction).await?;
            }
            sqlx::query("INSERT INTO schema_migrations (version, name) VALUES ($1, $2)")
                .bind(migration.version)
                .bind(migration.name)
                .execute(&mut *transaction)
                .await?;
            transaction.commit().await?;
            names.push(migration.name);
        }
        anyhow::Ok(names)
    }
    .await;
    unlock(&mut connection).await;
    result
}

/// Reverts the latest applied migration. Returns its name, or None when nothing is applied.
pub async fn revert(pool: &PgPool) -> anyhow::Result<Option<&'static str>> {
    let mut connection = pool.acquire().await?;
    prepare(&mut connection).await?;
    let result = async {
        let done = applied(&mut connection).await?;
        let Some(migration) = MIGRATIONS.iter().rev().find(|migration| done.contains(&migration.version)) else {
            return Ok(None);
        };
        let mut transaction = sqlx::Connection::begin(&mut *connection).await?;
        for statement in migration.down {
            sqlx::query(statement).execute(&mut *transaction).await?;
        }
        sqlx::query("DELETE FROM schema_migrations WHERE version = $1")
            .bind(migration.version)
            .execute(&mut *transaction)
            .await?;
        let typeorm_table: Option<String> =
            sqlx::query_scalar("SELECT to_regclass('public.migrations')::text").fetch_one(&mut *transaction).await?;
        if typeorm_table.is_some() {
            sqlx::query("DELETE FROM migrations WHERE timestamp = $1")
                .bind(migration.version)
                .execute(&mut *transaction)
                .await?;
        }
        transaction.commit().await?;
        anyhow::Ok(Some(migration.name))
    }
    .await;
    unlock(&mut connection).await;
    result
}

/// Each migration with whether it is applied.
pub async fn status(pool: &PgPool) -> anyhow::Result<Vec<(&'static str, bool)>> {
    let mut connection = pool.acquire().await?;
    prepare(&mut connection).await?;
    let done = applied(&mut connection).await;
    unlock(&mut connection).await;
    let done = done?;
    Ok(MIGRATIONS.iter().map(|migration| (migration.name, done.contains(&migration.version))).collect())
}
