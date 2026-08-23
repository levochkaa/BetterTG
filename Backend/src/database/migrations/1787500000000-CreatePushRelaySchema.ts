import type { MigrationInterface, QueryRunner } from 'typeorm'

export class CreatePushRelaySchema1787500000000 implements MigrationInterface {
    name = 'CreatePushRelaySchema1787500000000'

    async up(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`
            CREATE TABLE "app_attest_keys" (
                "key_id" varchar(255) NOT NULL,
                "public_key_pem" text NOT NULL,
                "receipt_encrypted" text NOT NULL,
                "sign_count" integer NOT NULL DEFAULT 0,
                "revoked" boolean NOT NULL DEFAULT false,
                "created_at" timestamptz NOT NULL DEFAULT now(),
                "updated_at" timestamptz NOT NULL DEFAULT now(),
                CONSTRAINT "PK_app_attest_keys" PRIMARY KEY ("key_id")
            )
        `)
        await queryRunner.query(`
            CREATE TABLE "installations" (
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
            )
        `)
        await queryRunner.query(
            `CREATE INDEX "IDX_installations_status" ON "installations" ("status")`,
        )
        await queryRunner.query(`
            CREATE TABLE "telegram_push_subscriptions" (
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
            )
        `)
    }

    async down(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`DROP TABLE "telegram_push_subscriptions"`)
        await queryRunner.query(`DROP INDEX "IDX_installations_status"`)
        await queryRunner.query(`DROP TABLE "installations"`)
        await queryRunner.query(`DROP TABLE "app_attest_keys"`)
    }
}
