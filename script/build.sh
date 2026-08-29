#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/device.sh"

PROJECT_NAME="BetterTG"
APP_NAME="BetterTG"
BUNDLE_ID="com.levochkaaa.BetterTG"
SCHEME="BetterTG"
DEFAULT_XCODE_PATH="/Applications/Xcode-26.6.0.app"
XCODE_PATH="$DEFAULT_XCODE_PATH"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode"
SIMULATOR_NAME="iPhone 17 Pro"
SIMULATOR_ID=""
DEVICE_ID=""
CODE_SIGNING_ALLOWED="YES"
IOS_VERSION="latest"
ACTION="build"
FULL_OUTPUT=0
USE_DEVICE=0
HAS_LAUNCH_ARGUMENTS=0
LAUNCH_ARGUMENTS=()

usage() {
  cat <<'EOF'
Usage: ./build.sh [build|run] [options]

Commands:
  build     Build BetterTG (default).
  run       Build, install, and launch BetterTG.

Options:
  --device  Use the available paired physical iPhone instead of Simulator.
  --device-id ID
            Use a specific paired physical iPhone identifier.
  --simulator NAME
            Simulator name. Default: iPhone 17 Pro.
  --simulator-id ID
            Use a specific simulator UDID instead of resolving by name and runtime.
  --ios VERSION|latest
            Simulator iOS runtime. Default: latest existing runtime for the simulator.
  --xcode PATH
            Xcode .app or Developer directory. Default: /Applications/Xcode-26.6.0.app.
  --configuration Debug|Release, --debug, --release
            Build configuration. Default: Debug.
  --launch-argument VALUE
            Argument passed to the launched app. Repeat for multiple arguments.
  --no-code-signing
            Compile without code signing. Not valid for run.
  --full-output, --verbose
            Print complete build output instead of concise progress.

Examples:
  ./build.sh run
  ./build.sh run --ios 26.5
  ./build.sh run --device
  ./build.sh run --device-id 00008150-00110D923412401C
  ./build.sh run --launch-argument=-example --launch-argument value
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
    --device-id)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --device-id requires an identifier" >&2
        exit 2
      fi
      USE_DEVICE=1
      DEVICE_ID="$2"
      shift
      ;;
    --simulator)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --simulator requires a name" >&2
        exit 2
      fi
      SIMULATOR_NAME="$2"
      shift
      ;;
    --simulator-id)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --simulator-id requires a UDID" >&2
        exit 2
      fi
      SIMULATOR_ID="$2"
      shift
      ;;
    --ios)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --ios requires VERSION or latest" >&2
        exit 2
      fi
      IOS_VERSION="$2"
      shift
      ;;
    --xcode)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --xcode requires an Xcode .app or Developer directory" >&2
        exit 2
      fi
      XCODE_PATH="$2"
      shift
      ;;
    --configuration)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --configuration requires Debug or Release" >&2
        exit 2
      fi
      case "$2" in
        Debug|debug) CONFIGURATION="Debug" ;;
        Release|release) CONFIGURATION="Release" ;;
        *)
          echo "error: unsupported configuration '$2' (expected Debug or Release)" >&2
          exit 2
          ;;
      esac
      shift
      ;;
    --debug)
      CONFIGURATION="Debug"
      ;;
    --release)
      CONFIGURATION="Release"
      ;;
    --launch-argument)
      if [[ $# -lt 2 ]]; then
        echo "error: --launch-argument requires a value" >&2
        exit 2
      fi
      LAUNCH_ARGUMENTS+=("$2")
      HAS_LAUNCH_ARGUMENTS=1
      shift
      ;;
    --launch-argument=*)
      LAUNCH_ARGUMENTS+=("${1#*=}")
      HAS_LAUNCH_ARGUMENTS=1
      ;;
    --no-code-signing)
      CODE_SIGNING_ALLOWED="NO"
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

  if [[ "$IOS_VERSION" != "latest" && ! "$IOS_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "error: unsupported iOS version '$IOS_VERSION' (expected VERSION or latest)" >&2
    exit 2
  fi

  if [[ "$USE_DEVICE" == "1" && -n "$SIMULATOR_ID" ]]; then
    echo "error: --simulator-id cannot be combined with --device or --device-id" >&2
    exit 2
  fi

  if [[ -n "$SIMULATOR_ID" && "$IOS_VERSION" != "latest" ]]; then
    echo "error: --simulator-id cannot be combined with --ios" >&2
    exit 2
  fi

  if [[ "$ACTION" != "run" && "$HAS_LAUNCH_ARGUMENTS" == "1" ]]; then
    echo "error: --launch-argument is only valid for run" >&2
    exit 2
  fi

  if [[ "$ACTION" == "run" && "$CODE_SIGNING_ALLOWED" == "NO" ]]; then
    echo "error: --no-code-signing cannot be used for run" >&2
    exit 2
  fi
}

configure_xcode() {
  local developer_dir="${XCODE_PATH%/}"
  local xcode_version
  case "$developer_dir" in
    *.app) developer_dir="$developer_dir/Contents/Developer" ;;
  esac

  if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
    echo "error: Xcode developer directory is invalid: $developer_dir" >&2
    exit 2
  fi

  export DEVELOPER_DIR="$developer_dir"
  xcode_version="$(xcodebuild -version)"
  xcode_version="${xcode_version%%$'\n'*}"
  echo "Using $xcode_version ($developer_dir)"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command '$1' is not installed" >&2
    exit 2
  fi
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
  local selected_id
  simctl_json="$(xcrun simctl list devices available -j)"

  if [[ "$IOS_VERSION" == "latest" ]]; then
    selected_id="$(
      jq -r --arg name "$SIMULATOR_NAME" '
        [
          .devices
          | to_entries[]
          | .key as $runtime
          | select($runtime | contains("com.apple.CoreSimulator.SimRuntime.iOS-"))
          | .value[]?
          | select((.isAvailable // true) and .name == $name)
          | {
              udid: .udid,
              version: (
                ($runtime | capture("iOS-(?<version>[0-9-]+)$")? | .version // "0")
                | split("-")
                | map(tonumber)
              )
            }
        ]
        | sort_by(.version)
        | last
        | .udid // empty
      ' <<< "$simctl_json"
    )"
  else
    local runtime="com.apple.CoreSimulator.SimRuntime.iOS-${IOS_VERSION//./-}"
    local fallback_runtime=""
    if [[ "$IOS_VERSION" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
      fallback_runtime="com.apple.CoreSimulator.SimRuntime.iOS-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
    fi

    selected_id="$(
      jq -r \
        --arg runtime "$runtime" \
        --arg fallbackRuntime "$fallback_runtime" \
        --arg name "$SIMULATOR_NAME" '
          [
            (.devices[$runtime] // .devices[$fallbackRuntime] // [])[]?
            | select((.isAvailable // true) and .name == $name)
          ]
          | first
          | .udid // empty
        ' <<< "$simctl_json"
    )"
  fi

  if [[ -z "$selected_id" ]]; then
    local os_suffix=""
    if [[ "$IOS_VERSION" != "latest" ]]; then
      os_suffix=" with iOS $IOS_VERSION"
    fi
    echo "error: no available simulator named '$SIMULATOR_NAME'$os_suffix" >&2
    return 1
  fi

  printf '%s\n' "$selected_id"
}

launch_on_device() {
  echo "Installing $APP_NAME on the connected iPhone..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_BUNDLE"

  echo "Launching $APP_NAME in the foreground on the connected iPhone..."
  if [[ "$HAS_LAUNCH_ARGUMENTS" == "1" ]]; then
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --activate \
      "$BUNDLE_ID" \
      "${LAUNCH_ARGUMENTS[@]}"
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

  if [[ "$HAS_LAUNCH_ARGUMENTS" == "1" ]]; then
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" "${LAUNCH_ARGUMENTS[@]}"
  else
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"
  fi
}

validate_configuration
require_command jq
require_command xcrun
configure_xcode

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
run_with_filtered_output python3 "$ROOT_DIR/td.py" --skip-resolve

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
)

if [[ "$CODE_SIGNING_ALLOWED" == "NO" ]]; then
  xcodebuild_args+=(
    "CODE_SIGNING_ALLOWED=NO"
    "CODE_SIGNING_REQUIRED=NO"
    "CODE_SIGN_IDENTITY="
  )
else
  xcodebuild_args+=("CODE_SIGNING_ALLOWED=YES")
fi

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
