# BetterTG Backend

Rich push relay for BetterTG. It accepts Telegram Web Push subscriptions, decrypts RFC 8291 payloads, classifies visible and service notifications, and sends the resulting payloads to APNs.

The backend never opens a Telegram session and does not store Telegram accounts, message history, chat identifiers, or notification text. Decrypted previews exist only in worker memory while an APNs request is built.

## Components

```text
Caddy → Nest API → Redis/BullMQ → Nest worker → APNs
                 ↘ PostgreSQL ↗
```

- `api` owns installation/App Attest endpoints and the public Web Push ingress.
- `worker` decrypts ciphertext, classifies Telegram events, and sends APNs requests.
- PostgreSQL stores encrypted APNs/Web Push secrets and installation metadata.
- Redis stores ciphertext-only jobs, idempotency envelopes, rate limits, and replay guards.
- Caddy terminates public HTTPS and enforces separate Web Push/management body limits.

## Local development

Requirements: Bun 1.4, Docker, and Docker Compose.

```bash
cd Backend
cp .env.example .env
bun install --frozen-lockfile
docker compose up -d postgres redis
bun run migration:run
bun run dev
```

Run the worker in another terminal:

```bash
bun run dev:worker
```

Or run the complete production-shaped stack:

```bash
docker compose up --build
curl http://localhost:8080/health/ready
SMOKE_REDIS_URL=redis://localhost:6380 bun run smoke:relay
```

Development defaults use APNs dry-run and bypass App Attest. These modes are rejected as production App Attest configuration and must not be exposed publicly.

## Verification

```bash
bun run format:check
bun run lint
bun test
bun run build
bun run migration:show
docker compose config --quiet
```

The test suite includes the RFC 8291 known-answer vector, ciphertext tampering, Telegram payload validation/classification, APNs payload budgeting, and a real local HTTP/2 exchange under Bun. Migration reversibility is checked with `migration:run`, `migration:revert`, then `migration:run` again.

Refresh Telegram's committed push catalog and the iOS English strings file with:

```bash
bun run catalog:update
git diff -- src/telegram-web-push/classification ../BetterTG/Resources
```

Catalog updates require human review. A newly introduced key remains non-visible until the regenerated allowlist is committed and tests describe its behavior.

## Production configuration

Before deployment:

1. Point a public DNS name at the server and set `SERVER_ADDRESS`/`PUBLIC_BASE_URL` to its HTTPS URL.
2. Create separate APNs `.p8` provider keys for Sandbox and Production. Set `APPLE_TEAM_ID`, each environment's `*_KEY_ID`, and either its inline `*_AUTH_KEY` or `*_AUTH_KEY_FILE`. Inline values accept PEM text with escaped newlines or base64-encoded PEM. Compose can mount the files read-only from `APNS_SANDBOX_AUTH_KEY_HOST_PATH` and `APNS_PRODUCTION_AUTH_KEY_HOST_PATH`. Legacy APNs keys that support both environments may be supplied in both pairs.
3. Set `APNS_DRY_RUN=false`.
4. Set `APP_ATTEST_MODE=enforce` and normally `APP_ATTEST_ALLOW_DEVELOPMENT=false`.
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

Export OpenTelemetry by setting `OTEL_EXPORTER_OTLP_ENDPOINT`. Important signals are:

- `webpush.ingress.requests` by result;
- `webpush.decryption.failures`;
- `webpush.classification` by `loc_key` and action;
- `webpush.processing.duration`;
- `apns.requests` by result/reason;
- `apns.connection.events` for connect/error/GOAWAY/close;
- BullMQ queue depth and oldest job age.

Alert on sustained decrypt failures, any unknown push key, APNs authentication failures, growing queue age, or a large group of invalid device tokens. Logs never include APNs tokens, bearer/capability tokens, Web Push keys, ciphertext, `loc_args`, routing identifiers, or decrypted payloads.

## Incident handling

- APNs `429`/`5xx`, timeouts, connection errors, and expired provider JWTs retry with bounded exponential backoff and jitter.
- APNs `BadDeviceToken`, `DeviceTokenNotForTopic`, `ExpiredToken`, and `Unregistered` disable the installation until iOS uploads a fresh device token.
- Unknown Telegram keys fail closed and emit a metric; update the committed catalog before allowing them.
- If Redis is unavailable, Web Push ingress returns `503` instead of acknowledging a lost notification.
- Revoking/deleting an installation physically removes APNs and Web Push key material. Logout also deregisters the TDLib Web Push endpoint and revokes the relay subscription.

Real Telegram → APNs acceptance still requires a public HTTPS domain, Apple provider credentials, an App Attest-capable physical iPhone, and a Telegram account on that device.
