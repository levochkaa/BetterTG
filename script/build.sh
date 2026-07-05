#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/xcode_env.sh"
PROJECT_NAME="BetterTG"
SCHEME="BetterTG"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_ID="${SIMULATOR_ID:-}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}"
FULL_OUTPUT=0

usage() {
  cat <<'EOF'
Usage: ./script/build.sh [--full-output|--verbose]

By default, build output is filtered to error and warning lines. Pass
--full-output or --verbose to print the complete command output.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

filter_build_output() {
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
  "$@" 2>&1 | filter_build_output
  local command_status=${PIPESTATUS[0]}
  set -e

  if [[ "$command_status" -ne 0 ]]; then
    echo "error: command failed: $*" >&2
  fi

  return "$command_status"
}

resolve_swift_packages() {
  run_with_filtered_output xcodebuild \
    -resolvePackageDependencies \
    -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -packageAuthorizationProvider netrc \
    -scmProvider system \
    -skipPackagePluginValidation \
    -skipMacroValidation
}

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

validate_configuration
run_with_filtered_output "$ROOT_DIR/script/generate_xcodeproj.sh"
resolve_swift_packages
run_with_filtered_output env BETTERTG_TD_SKIP_RESOLVE=1 python3 "$ROOT_DIR/td.py"

if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(simulator_id)"
fi

xcodebuild_args=(
  -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID"
  -packageAuthorizationProvider netrc
  -scmProvider system
  -skipPackagePluginValidation
  -skipMacroValidation
  "CODE_SIGNING_ALLOWED=$CODE_SIGNING_ALLOWED"
)

run_with_filtered_output xcodebuild "${xcodebuild_args[@]}" build

if [[ "$FULL_OUTPUT" == "1" ]]; then
  echo "BetterTG built successfully"
fi
