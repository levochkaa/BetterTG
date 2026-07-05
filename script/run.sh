#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/xcode_env.sh"
APP_NAME="BetterTG"
BUNDLE_ID="com.levochkaaa.BetterTG"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"

case "$CONFIGURATION" in
  Debug|Release)
    ;;
  *)
    echo "error: unsupported CONFIGURATION '$CONFIGURATION' (expected Debug or Release)" >&2
    exit 2
    ;;
esac

simulator_id() {
  local simctl_json
  simctl_json="$(xcrun simctl list devices available -j)"
  SIMCTL_JSON="$simctl_json" python3 - "$SIMULATOR_NAME" <<'PY'
import json
import os
import re
import sys

target_name = sys.argv[1]
data = json.loads(os.environ["SIMCTL_JSON"])
matches = []
for runtime, devices in data.get("devices", {}).items():
    version_match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    version = tuple(map(int, version_match.groups())) if version_match else (0, 0)
    for device in devices:
        if device.get("name") == target_name and device.get("isAvailable", False):
            matches.append((version, device["udid"]))

if not matches:
    raise SystemExit(f"error: no available simulator named {target_name!r}")

print(sorted(matches)[-1][1])
PY
}

"$ROOT_DIR/script/build.sh" --full-output

SIMULATOR_ID="$(simulator_id)"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphonesimulator/$APP_NAME.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
open -a Simulator
xcrun simctl install "$SIMULATOR_ID" "$APP_BUNDLE"
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"
