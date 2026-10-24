# BetterTG Backend

Rich push relay for BetterTG, written in Rust. It accepts Telegram Web Push subscriptions, decrypts both Telegram's legacy `aesgcm` profile and RFC 8291 `aes128gcm` payloads, classifies visible and service notifications, and sends the resulting payloads to APNs.

The backend never opens a Telegram session and does not store Telegram accounts, message history, chat identifiers, or notification text. Decrypted previews exist only in worker memory while an APNs request is built, and briefly in Redis for the Notification Service Extension to fetch once.

## Components

```text
Caddy → API → Redis queue → worker → APNs
          ↘ PostgreSQL ↗
```

One binary, `bettertg-backend`, runs each role:

- `bettertg-backend api` owns installation/App Attest endpoints, the public Web Push ingress and the one-time notification content endpoint (axum).
- `bettertg-backend worker` decrypts ciphertext, classifies Telegram events, and sends APNs requests over one persistent HTTP/2 connection per APNs host.
- `bettertg-backend migrate run|revert|show` manages the PostgreSQL schema.

PostgreSQL stores encrypted APNs/Web Push secrets and installation metadata. Redis stores ciphertext-only jobs, idempotency envelopes, rate limits, replay guards and one-time notification content. Caddy terminates public HTTPS and enforces separate Web Push/management body limits.

The queue lives under `queue:telegram-web-push:` in Redis: a job ID is accepted once, a job is retried five times with exponential backoff from one second, a worker that dies mid-job hands the job back after about 30 seconds, completed jobs disappear at once, and failed jobs are kept for an hour, at most 100.

## Local development

Requirements: a stable Rust toolchain (`rustup`), Docker and Docker Compose.

```bash
cd Backend
cp .env.example .env
docker compose up -d postgres redis
cargo run -- migrate run
cargo run -- api
```

Run the worker in another terminal:

```bash
cargo run -- worker
```

Or run the complete production-shaped stack:

```bash
docker compose up --build
curl http://localhost:8080/health/ready
SMOKE_REDIS_URL=redis://localhost:6380 cargo run --bin smoke-relay
```

On a VPS that already has a system reverse proxy bound to ports 80 and 443, publish only the
API on loopback and leave the Compose Caddy service stopped:

```bash
docker compose -f compose.yaml -f compose.vps.yaml up --build -d \
  postgres redis migrate api worker
```

Point the host reverse proxy at `127.0.0.1:8080`. PostgreSQL and Redis remain bound to loopback.
When APNs keys are bind-mounted with mode `0600`, set `BETTERTG_WORKER_UID` and
`BETTERTG_WORKER_GID` to the numeric owner reported by `id -u` and `id -g` on the VPS.

Development defaults use APNs dry-run and bypass App Attest. These modes are rejected as production App Attest configuration and must not be exposed publicly. Swagger UI for the management API is at `/api/docs` while `SWAGGER_ENABLED=true`.

## Verification

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
BETTERTG_TEST_DATABASE_URL=postgresql://bettertg:bettertg@localhost:5433/bettertg \
BETTERTG_TEST_REDIS_URL=redis://localhost:6380/0 \
cargo test
cargo run -- migrate show
docker compose config --quiet
```

The tests include the RFC 8291 known-answer vector, byte-for-byte agreement with the `http_ece` package the Node backend used for both encodings, ciphertext tampering, Telegram payload validation/classification, APNs payload budgeting, App Attest attestation and assertion checks against a synthetic certificate chain, a real local HTTP/2 exchange with a fake APNs server, and values encrypted by the Node backend. With the two `BETTERTG_TEST_*` variables set, the queue and the whole ingress → queue → worker → APNs path also run against real PostgreSQL and Redis. CI checks migration reversibility with `migrate run`, `migrate revert`, then `migrate run` again, and runs the encrypted relay smoke against the API and worker.

Refresh Telegram's committed push catalog and the iOS English strings file with:

```bash
cargo run --bin update-push-catalog
git diff -- src/web_push/catalog.rs ../BetterTG/Resources
```

Catalog updates require human review. A newly introduced key remains non-visible until the regenerated allowlist is committed and tests describe its behavior.

## Moving from the NestJS backend

The Rust backend reads the same environment variables, uses the same PostgreSQL schema and the same encrypted value format, so it runs against an existing database and keyring unchanged. `migrate run` adopts a database TypeORM migrated: migrations recorded in TypeORM's `migrations` table count as applied. Installation bearer tokens, Web Push endpoints and stored keys keep working, so devices don't need to register again.

Jobs still waiting in the old BullMQ queue (`bull:telegram-web-push:*`) are not picked up. Drain the old worker before switching, or accept that pushes received in the last moments before the switch are lost.

## Production configuration

Before deployment:

1. Point a public DNS name at the server and set `SERVER_ADDRESS`/`PUBLIC_BASE_URL` to its HTTPS URL.
2. Create separate APNs `.p8` provider keys for Sandbox and Production. Set `APPLE_TEAM_ID`, each environment's `*_KEY_ID`, and either its inline `*_AUTH_KEY` or `*_AUTH_KEY_FILE`. Inline values accept PEM text with escaped newlines or base64-encoded PEM. Compose can mount the files read-only from `APNS_SANDBOX_AUTH_KEY_HOST_PATH` and `APNS_PRODUCTION_AUTH_KEY_HOST_PATH`. Legacy APNs keys that support both environments may be supplied in both pairs. The worker refuses to start with a key that isn't a P-256 PKCS#8 key.
3. Set `APNS_DRY_RUN=false`.
4. Set `APP_ATTEST_MODE=enforce`. Production App Attest keys are always accepted; `APP_ATTEST_ALLOW_DEVELOPMENT=true` additionally accepts keys from the development environment, so leave it `false` in production.
5. Generate independent 32-byte values for the encryption key and management-token pepper:

```bash
openssl rand -base64 32
openssl rand -base64 32
```

6. Set `ENCRYPTION_CURRENT_KEY_ID`, `ENCRYPTION_KEYS`, and `MANAGEMENT_TOKEN_PEPPER`. Never reuse the example development values.
7. Configure `BETTERTG_RELAY_BASE_URL` for the iOS Release configuration. The repository intentionally leaves it empty until a production domain exists.
8. Enable Push Notifications and App Attest for `com.levochkaaa.BetterTG` in the Apple developer account and ensure the provisioning profile contains both entitlements.

The production process refuses non-HTTPS public URLs, App Attest bypass, development encryption keys, custom APNs hosts, or missing APNs credentials when dry-run is disabled.

## Secret rotation

`ENCRYPTION_KEYS` is a comma-separated keyring such as `v1:<base64>,v2:<base64>`. Set `ENCRYPTION_CURRENT_KEY_ID=v2` to encrypt new values with `v2` while retaining `v1` for reads. Re-encrypt existing rows before removing an old key. Changing `MANAGEMENT_TOKEN_PEPPER` invalidates every installation bearer token and therefore requires re-registration by all clients.

APNs token-signing JWTs are cached independently for Sandbox and Production for 50 minutes. Rotating an Apple `.p8` key requires replacing that environment's key ID and auth key, then restarting workers so existing HTTP/2 sessions close.

## Backup and restore

PostgreSQL backups contain encrypted secret material and must themselves be encrypted and access-controlled. Redis is intentionally not the source of truth, but AOF and `noeviction` are enabled so accepted jobs survive ordinary restarts.

Example logical backup:

```bash
docker compose exec -T postgres pg_dump -U bettertg -Fc bettertg > bettertg.dump
```

Restore into a clean database, start `migrate`, then start API/worker. After restoration, verify `/health/ready`, create a disposable installation, and deliver a synthetic encrypted push before changing DNS.

## Operational signals

Export OpenTelemetry over OTLP/HTTP by setting `OTEL_EXPORTER_OTLP_ENDPOINT`. Important signals are:

- `webpush.ingress.requests` by status;
- `webpush.decryption.failures`;
- `webpush.classification` by `loc_key` and action;
- `webpush.processing.duration`;
- `apns.requests` by status/reason;
- `apns.connection.events` for connect/error/GOAWAY/close.

HTTP request spans carry the route template, never the path, so capability and content tokens stay out of telemetry. Alert on sustained decrypt failures, any unknown push key, APNs authentication failures, a growing queue (`LLEN queue:telegram-web-push:wait` plus `ZCARD queue:telegram-web-push:delayed`), or a large group of invalid device tokens. Logs never include APNs tokens, bearer/capability tokens, Web Push keys, ciphertext, `loc_args`, routing identifiers, or decrypted payloads.

## Incident handling

- APNs `429`/`5xx`, timeouts, connection errors, and expired provider JWTs retry with bounded exponential backoff and jitter.
- APNs `BadDeviceToken`, `DeviceTokenNotForTopic`, `ExpiredToken`, and `Unregistered` disable the installation until iOS uploads a fresh device token.
- A push that can't be decrypted or read fails at once without retrying, and counts in `webpush.decryption.failures`.
- Unknown Telegram keys fail closed and emit a metric; update the committed catalog before allowing them.
- If Redis is unavailable, Web Push ingress returns `503` instead of acknowledging a lost notification.
- Revoking/deleting an installation physically removes APNs and Web Push key material. Logout also deregisters the TDLib Web Push endpoint and revokes the relay subscription.

Real Telegram → APNs acceptance still requires a public HTTPS domain, Apple provider credentials, an App Attest-capable physical iPhone, and a Telegram account on that device.
