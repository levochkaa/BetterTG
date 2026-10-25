#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_PATH="$ROOT_DIR/BetterTG/Secret/Secret.swift"
LOCAL_CONFIG_PATH="$ROOT_DIR/Configuration/Local.xcconfig"
OFFICIAL_TEAM_ID="7Z2WHPKU8W"
OFFICIAL_BUNDLE_ID="com.levochkaaa.BetterTG"

API_ID=""
API_HASH=""
TEAM_ID=""
BUNDLE_ID=""
RELAY_URL=""
RELAY_URL_SET=0

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Configures a checkout for building. Asks for anything it needs that the options don't give.

Options:
  --api-id ID          Telegram api_id from https://my.telegram.org.
  --api-hash HASH      Telegram api_hash from https://my.telegram.org.
  --team ID            Apple Developer Team ID that signs device builds.
  --bundle-id ID       Bundle ID of the app. The notification extension appends .NotificationService and the
                       App Group is group.<bundle ID>.
  --relay-url URL      Push relay of your own Backend deployment.
  --no-relay           Build without the push relay.
  -h, --help           Show this help.

The api_id and api_hash go to BetterTG/Secret/Secret.swift. Team, bundle ID and relay go to
Configuration/Local.xcconfig. Git ignores both files.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_value() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-id)
      require_value "$@"
      API_ID="$2"
      shift 2
      ;;
    --api-hash)
      require_value "$@"
      API_HASH="$2"
      shift 2
      ;;
    --team)
      require_value "$@"
      TEAM_ID="$2"
      shift 2
      ;;
    --bundle-id)
      require_value "$@"
      BUNDLE_ID="$2"
      shift 2
      ;;
    --relay-url)
      require_value "$@"
      RELAY_URL="$2"
      RELAY_URL_SET=1
      shift 2
      ;;
    --no-relay)
      RELAY_URL=""
      RELAY_URL_SET=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option $1"
      ;;
  esac
done

INTERACTIVE=0
[[ -t 0 ]] && INTERACTIVE=1

ask() {
  local prompt="$1" answer
  read -r -p "$prompt" answer
  printf '%s' "$answer"
}

# MARK: Telegram API credentials

if [[ -z "$API_ID" && -z "$API_HASH" && -f "$SECRET_PATH" ]]; then
  echo "Keeping the api_id and api_hash in BetterTG/Secret/Secret.swift."
else
  if [[ -z "$API_ID" || -z "$API_HASH" ]]; then
    [[ "$INTERACTIVE" == "1" ]] || die "pass --api-id and --api-hash from https://my.telegram.org"
    echo "Create an app at https://my.telegram.org → API development tools."
    [[ -n "$API_ID" ]] || API_ID="$(ask "api_id: ")"
    [[ -n "$API_HASH" ]] || API_HASH="$(ask "api_hash: ")"
  fi
  [[ "$API_ID" =~ ^[0-9]+$ ]] || die "api_id must be a number"
  [[ "$API_HASH" =~ ^[0-9a-fA-F]{32}$ ]] || die "api_hash must be 32 hexadecimal characters"

  mkdir -p "$(dirname "$SECRET_PATH")"
  # The values are XORed with a random salt so that `strings` on the app binary doesn't show them.
  API_ID="$API_ID" API_HASH="$API_HASH" python3 - "$SECRET_PATH" <<'PYTHON'
import os
import sys

salt = os.urandom(64)


def array(values, indent):
    rows = [values[i : i + 8] for i in range(0, len(values), 8)]
    return "\n".join(indent + " ".join(f"0x{byte:02X}," for byte in row) for row in rows)


def encoded(value):
    data = value.encode()
    return array([byte ^ salt[i % len(salt)] for i, byte in enumerate(data)], " " * 12)


source = f"""// Secret.swift

public struct Secret {{
    // MARK: Private

    private static let salt: [UInt8] = [
{array(list(salt), " " * 8)}
    ]

    // MARK: Public

    public static var apiId: Int {{
        let encoded: [UInt8] = [
{encoded(os.environ["API_ID"])}
        ]

        return Int(decode(encoded, cipher: salt))!
    }}

    public static var apiHash: String {{
        let encoded: [UInt8] = [
{encoded(os.environ["API_HASH"])}
        ]

        return decode(encoded, cipher: salt)
    }}

    private init() {{}} // Just to disable instantiation

    public static func decode(_ encoded: [UInt8], cipher: [UInt8]) -> String {{
        String(decoding: encoded.enumerated().map {{ offset, element in
            element ^ cipher[offset % cipher.count]
        }}, as: UTF8.self)
    }}
}}
"""

path = sys.argv[1]
descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(descriptor, "w") as file:
    file.write(source)
PYTHON
  echo "Wrote BetterTG/Secret/Secret.swift."
fi

# MARK: Signing identity and push relay

read_local_setting() {
  [[ -f "$LOCAL_CONFIG_PATH" ]] || return 0
  sed -n "s/^$1 = //p" "$LOCAL_CONFIG_PATH" | tail -n 1
}

if [[ -z "$TEAM_ID" && -z "$BUNDLE_ID" && "$RELAY_URL_SET" == "0" ]]; then
  if [[ -f "$LOCAL_CONFIG_PATH" ]]; then
    echo "Keeping the signing settings in Configuration/Local.xcconfig."
    exit 0
  fi
  if [[ "$INTERACTIVE" == "1" ]]; then
    echo "Simulator builds work without signing settings. Device builds need your own Apple Developer team."
    TEAM_ID="$(ask "Team ID (Enter to skip): ")"
  fi
  if [[ -z "$TEAM_ID" ]]; then
    echo "Skipped signing settings. Run ./setup.sh --team ID --bundle-id ID before building for a device."
    exit 0
  fi
fi

[[ -n "$TEAM_ID" ]] || TEAM_ID="$(read_local_setting DEVELOPMENT_TEAM)"
[[ -n "$BUNDLE_ID" ]] || BUNDLE_ID="$(read_local_setting BETTERTG_BUNDLE_ID)"
if [[ -z "$BUNDLE_ID" ]]; then
  suggested="com.$(id -un | tr -cd '[:alnum:]-').BetterTG"
  if [[ "$INTERACTIVE" == "1" ]]; then
    BUNDLE_ID="$(ask "Bundle ID [$suggested]: ")"
  fi
  [[ -n "$BUNDLE_ID" ]] || BUNDLE_ID="$suggested"
fi
[[ -z "$TEAM_ID" || "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "a Team ID is 10 uppercase letters and digits"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || die "invalid bundle ID $BUNDLE_ID"
if [[ -n "$TEAM_ID" && "$TEAM_ID" != "$OFFICIAL_TEAM_ID" && "$BUNDLE_ID" == "$OFFICIAL_BUNDLE_ID" ]]; then
  die "$OFFICIAL_BUNDLE_ID belongs to the official team; pass your own --bundle-id"
fi

# The official bundle ID keeps the official relay unless a relay is given.
WRITE_RELAY=1
if [[ "$RELAY_URL_SET" == "0" ]]; then
  if [[ -f "$LOCAL_CONFIG_PATH" ]] && grep -q '^BETTERTG_RELAY_BASE_URL = ' "$LOCAL_CONFIG_PATH"; then
    RELAY_URL="$(read_local_setting BETTERTG_RELAY_BASE_URL | sed 's|:/\$()/|://|')"
  elif [[ "$BUNDLE_ID" != "$OFFICIAL_BUNDLE_ID" ]]; then
    # push.bettertg.su accepts only the official app: App Attest and APNs both check the bundle ID.
    if [[ "$INTERACTIVE" == "1" ]]; then
      RELAY_URL="$(ask "Push relay URL of your Backend deployment (Enter to build without push): ")"
    fi
  else
    WRITE_RELAY=0
  fi
fi
[[ -z "$RELAY_URL" || "$RELAY_URL" =~ ^https?://[^[:space:]]+$ ]] || die "invalid relay URL $RELAY_URL"

mkdir -p "$(dirname "$LOCAL_CONFIG_PATH")"
{
  echo "// Local.xcconfig"
  echo "// Written by ./setup.sh. Overrides Configuration/BetterTG.xcconfig for this checkout."
  echo
  [[ -z "$TEAM_ID" ]] || echo "DEVELOPMENT_TEAM = $TEAM_ID"
  echo "BETTERTG_BUNDLE_ID = $BUNDLE_ID"
  if [[ "$WRITE_RELAY" == "1" ]]; then
    # `//` starts an xcconfig comment, so `$()` splits it.
    echo "BETTERTG_RELAY_BASE_URL = ${RELAY_URL/:\/\//:/\$()/}"
  fi
} >"$LOCAL_CONFIG_PATH"
relay_summary="${RELAY_URL:-off}"
[[ "$WRITE_RELAY" == "1" ]] || relay_summary="official"
echo "Wrote Configuration/Local.xcconfig: bundle ID $BUNDLE_ID${TEAM_ID:+, team $TEAM_ID}, relay $relay_summary."
