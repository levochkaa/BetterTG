#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/xcode_env.sh"
source "$ROOT_DIR/script/device.sh"

PROJECT_NAME="BetterTG"
APP_NAME="BetterTG"
BUNDLE_ID="com.levochkaaa.BetterTG"
SCHEME="BetterTG"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_OS="${SIMULATOR_OS:-}"
SIMULATOR_ID="${SIMULATOR_ID:-}"
DEVICE_ID="${DEVICE_ID:-}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}"
ACTION="build"
FULL_OUTPUT=0
USE_DEVICE=0

usage() {
  cat <<'EOF'
Usage: ./build.sh [build|run] [--device] [--full-output|--verbose]

Commands:
  build     Build BetterTG (default).
  run       Build, install, and launch BetterTG.

Options:
  --device  Use the available paired physical iPhone instead of Simulator.
            Set DEVICE_ID to choose a specific iPhone when more than one is available.
  --full-output, --verbose
            Print complete build output instead of concise progress.

Examples:
  ./build.sh run
  SIMULATOR_OS=26.5 ./build.sh run
  ./build.sh run --device
  RUN_ARGUMENTS="-example value" ./build.sh run --device
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    build|run)
      ACTION="$1"
      shift
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      USE_DEVICE=1
      ;;
    --full-output|--verbose)
      FULL_OUTPUT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

validate_configuration() {
  case "$CONFIGURATION" in
    Debug|Release)
      ;;
    *)
      echo "error: unsupported CONFIGURATION '$CONFIGURATION' (expected Debug or Release)" >&2
      exit 2
      ;;
  esac
}

filter_command_output() {
  if [[ "$FULL_OUTPUT" == "1" ]]; then
    cat
    return
  fi

  sed \
    -e '/warning: Metadata extraction disabled by --disable/d' \
    -e '/warning: Metadata extraction skipped\. No AppIntents\.framework dependency found\./d' |
    grep -En "error:|warning:" || true
}

run_with_filtered_output() {
  if [[ "$FULL_OUTPUT" == "1" ]]; then
    "$@"
    return
  fi

  set +e
  "$@" 2>&1 | filter_command_output
  local command_status=${PIPESTATUS[0]}
  set -e

  if [[ "$command_status" -ne 0 ]]; then
    echo "error: command failed: $*" >&2
  fi

  return "$command_status"
}

run_xcodebuild() {
  if [[ "$FULL_OUTPUT" == "1" ]]; then
    "$@"
    return
  fi

  if command -v xcbeautify >/dev/null 2>&1; then
    set +e
    "$@" 2>&1 | xcbeautify
    local command_status=${PIPESTATUS[0]}
    set -e

    if [[ "$command_status" -ne 0 ]]; then
      echo "error: command failed: $*" >&2
    fi
    return "$command_status"
  fi

  run_with_filtered_output "$@"
}

resolve_swift_packages() {
  run_xcodebuild xcodebuild \
    -resolvePackageDependencies \
    -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -packageAuthorizationProvider netrc \
    -scmProvider system \
    -skipPackagePluginValidation \
    -skipMacroValidation
}

tdlib_update_model_exists() {
  [[ -f "$DERIVED_DATA_PATH/SourcePackages/checkouts/TDLibKit/Sources/TDLibKit/Generated/Models/Update.swift" ]] ||
    [[ -f "$DERIVED_DATA_PATH/SourcePackages/checkouts/tdlibkit/Sources/TDLibKit/Generated/Models/Update.swift" ]]
}

simulator_id() {
  local simctl_json
  simctl_json="$(xcrun simctl list devices available -j)"
  SIMCTL_JSON="$simctl_json" python3 - "$SIMULATOR_NAME" "$SIMULATOR_OS" <<'PY'
import json
import os
import re
import sys

target_name = sys.argv[1]
target_os = sys.argv[2]
data = json.loads(os.environ["SIMCTL_JSON"])
matches = []
for runtime, devices in data.get("devices", {}).items():
    version_match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    version = tuple(map(int, version_match.groups())) if version_match else (0, 0)
    version_string = ".".join(map(str, version))
    if target_os and version_string != target_os:
        continue
    for device in devices:
        if device.get("name") == target_name and device.get("isAvailable", False):
            matches.append((version, device["udid"]))

if not matches:
    os_suffix = f" with iOS {target_os}" if target_os else ""
    raise SystemExit(f"error: no available simulator named {target_name!r}{os_suffix}")

print(sorted(matches)[-1][1])
PY
}

launch_on_device() {
  echo "Installing $APP_NAME on the connected iPhone..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_BUNDLE"

  echo "Launching $APP_NAME in the foreground on the connected iPhone..."
  if [[ -n "${RUN_ARGUMENTS:-}" ]]; then
    local launch_arguments=()
    read -r -a launch_arguments <<< "$RUN_ARGUMENTS"
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --activate \
      "$BUNDLE_ID" \
      "${launch_arguments[@]}"
  else
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --activate \
      "$BUNDLE_ID"
  fi
}

launch_on_simulator() {
  xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
  open -a Simulator
  xcrun simctl install "$SIMULATOR_ID" "$APP_BUNDLE"

  if [[ -n "${RUN_ARGUMENTS:-}" ]]; then
    local launch_arguments=()
    read -r -a launch_arguments <<< "$RUN_ARGUMENTS"
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" "${launch_arguments[@]}"
  else
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"
  fi
}

validate_configuration

if [[ "$USE_DEVICE" == "1" ]]; then
  echo "Finding a connected iPhone..."
  DEVICE_ID="$(resolve_connected_iphone_id "$DEVICE_ID")"
  validate_connected_iphone "$DEVICE_ID"
  destination="platform=iOS,id=$DEVICE_ID"
  product_platform="iphoneos"
else
  if [[ -z "$SIMULATOR_ID" ]]; then
    SIMULATOR_ID="$(simulator_id)"
  fi
  destination="platform=iOS Simulator,id=$SIMULATOR_ID"
  product_platform="iphonesimulator"
fi

echo "Generating the Xcode project..."
run_with_filtered_output "$ROOT_DIR/script/generate_xcodeproj.sh"

if ! tdlib_update_model_exists; then
  echo "Resolving Swift packages for the initial build..."
  resolve_swift_packages
fi

echo "Updating generated TDLib models..."
run_with_filtered_output env BETTERTG_TD_SKIP_RESOLVE=1 python3 "$ROOT_DIR/td.py"

xcodebuild_args=(
  -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -destination "$destination"
  -packageAuthorizationProvider netrc
  -scmProvider system
  -skipPackagePluginValidation
  -skipMacroValidation
  "CODE_SIGNING_ALLOWED=$CODE_SIGNING_ALLOWED"
)

if [[ "$USE_DEVICE" == "1" ]]; then
  xcodebuild_args+=(
    -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration
  )
fi

echo "Building $APP_NAME for $destination..."
build_started_at=$SECONDS
run_xcodebuild xcodebuild "${xcodebuild_args[@]}" build
echo "$APP_NAME built in $((SECONDS - build_started_at))s."

if [[ "$ACTION" == "build" ]]; then
  exit 0
fi

APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-$product_platform/$APP_NAME.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

if [[ "$USE_DEVICE" == "1" ]]; then
  launch_on_device
else
  launch_on_simulator
fi
