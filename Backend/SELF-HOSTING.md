# Running your own relay

The relay at `push.bettertg.su` accepts only the official app: App Attest checks the app's team and bundle ID, and APNs delivers only to the bundle ID its key belongs to. A fork signed with its own bundle ID needs its own relay, or builds without one and shows notifications only while it is open (`./setup.sh --no-relay`).

## What you need

- An Apple Developer Program membership. The free tier has no push notifications or App Attest.
- A Linux server with Docker and Docker Compose, ports 80 and 443 open, and about 1 GB of free memory. The images build on the server; on a one-CPU server, cross-compile instead, as [README.md](README.md#local-development) shows.
- A DNS name for the relay, such as `push.example.com`, pointing at the server.

## 1. Configure the app

From the repository root:

```bash
./setup.sh --team TEAMID --bundle-id com.example.BetterTG --relay-url https://push.example.com
```

`Configuration/Local.xcconfig` now holds your team, your bundle ID, the App Group `group.com.example.BetterTG` and your relay. Build once for a device with `./build.sh run --device`: Xcode's automatic signing registers the App ID and the App Group and enables Push Notifications, App Attest and Communication Notifications from the entitlements.

## 2. Create an APNs key

In the developer account, under Certificates, Identifiers & Profiles → Keys, create a key with Apple Push Notifications service (APNs), for both Sandbox and Production. Download the `.p8` file and note its key ID and your team ID.

Debug builds from Xcode receive Sandbox pushes and attest in the development environment; TestFlight and App Store builds use Production.

## 3. Configure the relay

On the server, copy the `Backend` directory and create `.env` from the example:

```bash
cd Backend
cp .env.example .env
mkdir -p secrets && cp AuthKey_KEYID.p8 secrets/ && chmod 600 secrets/AuthKey_KEYID.p8
openssl rand -base64 32   # the encryption key
openssl rand -base64 32   # the management token pepper
```

Set these in `.env`:

```bash
NODE_ENV=production
SERVER_ADDRESS=push.example.com
PUBLIC_BASE_URL=https://push.example.com
HTTP_PORT=80
HTTPS_PORT=443

BUNDLE_ID=com.example.BetterTG
APPLE_TEAM_ID=TEAMID
APNS_SANDBOX_KEY_ID=KEYID
APNS_SANDBOX_AUTH_KEY_HOST_PATH=./secrets/AuthKey_KEYID.p8
APNS_PRODUCTION_KEY_ID=KEYID
APNS_PRODUCTION_AUTH_KEY_HOST_PATH=./secrets/AuthKey_KEYID.p8
APNS_DRY_RUN=false

ENCRYPTION_CURRENT_KEY_ID=v1
ENCRYPTION_KEYS=v1:<the encryption key>
MANAGEMENT_TOKEN_PEPPER=<the pepper>

APP_ATTEST_MODE=enforce
# true while you test Debug builds from Xcode; false once only TestFlight and App Store builds use the relay.
APP_ATTEST_ALLOW_DEVELOPMENT=true
SWAGGER_ENABLED=false
```

Compose mounts the key files into the worker and points it at them. When a key file is mode `0600`, also set `BETTERTG_WORKER_UID` and `BETTERTG_WORKER_GID` to its owner's `id -u` and `id -g`.

[README.md](README.md#production-configuration) explains each setting; the relay refuses to start in production with development keys, App Attest bypass or missing APNs credentials.

## 4. Start it

```bash
docker compose up --build -d
docker compose ps
curl https://push.example.com/health/ready
```

Compose runs PostgreSQL, Redis, the migrations, the API, the worker and Caddy, which gets the HTTPS certificate for `SERVER_ADDRESS`. On a server whose own reverse proxy already holds ports 80 and 443, use `compose.vps.yaml` as [README.md](README.md#local-development) describes and point that proxy at `127.0.0.1:8080`.

## 5. Check a notification

Install the app, log in, allow notifications and send yourself a message from another account while the app is in the background. The worker logs `apns.delivered` for each notification it sends:

```bash
docker compose logs -f worker
```

`401` responses to `POST /api/v1/installations` in the app's log mean App Attest rejected it: check `BUNDLE_ID`, `APPLE_TEAM_ID` and `APP_ATTEST_ALLOW_DEVELOPMENT`. The Simulator has no App Attest, so test on a device.

## Privacy

Your relay decrypts the notifications it delivers and sees each one's sender, chat title and preview. Publish your own privacy policy, and point the Privacy Policy and Terms of Service rows in `SettingsViewController` at your pages; they open bettertg.su, which describes the official relay. `Website/privacy.html` is a starting point.
