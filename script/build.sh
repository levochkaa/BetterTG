#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/device.sh"
ORIGINAL_ARGS=("$@")

PROJECT_NAME="BetterTG"
APP_NAME="BetterTG"
BUNDLE_ID="com.levochkaaa.BetterTG"
SCHEME="BetterTG"
DEFAULT_XCODE_PATH="/Applications/Xcode-26.6.0.app"
XCODE_PATH="$DEFAULT_XCODE_PATH"
CONFIGURATION="Debug"
DERIVED_DATA_PATH=""
DERIVED_DATA_OVERRIDDEN=0
PACKAGE_CACHE_ROOT="$HOME/Library/Developer/Xcode/PackageGraphCaches"
PACKAGE_CACHE_ROOT_OVERRIDDEN=0
PACKAGE_GRAPH_KEY=""
CLONED_SOURCE_PACKAGES_DIR_PATH=""
TOOLCHAIN_KEY=""
BUILD_LOCK_PATH="/tmp/bettertg-build.lock"
BUILD_LOCK_HELD=0
XCODEBUILD_LOG_DIR="$ROOT_DIR/.build/logs/xcodebuild"
LAST_XCODEBUILD_LOG_PATH=""
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
ATTACH_CONSOLE=0
SKIP_BUILD=0
SIMULATOR_BOOT_TIMEOUT_SECONDS=120

usage() {
  cat <<'EOF'
Usage: ./build.sh [build|run|clean-intermediates] [options]

Commands:
  build     Build BetterTG (default).
  run       Build, install, and launch BetterTG.
  clean-intermediates
            Remove compilation, index, module, and SDK-stat intermediates while preserving products and Swift packages.

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
  --derived-data PATH
            DerivedData path. Default: .build/xcodebuild-derived-data/<Xcode version>.
  --cloned-source-packages-dir-path PATH
            Root for graph-keyed Swift package caches.
  --xcodebuild-log-dir PATH
            Full xcodebuild log directory. Default: .build/logs/xcodebuild.
  --configuration Debug|Release, --debug, --release
            Build configuration. Default: Debug.
  --launch-argument VALUE
            Argument passed to the launched app. Repeat for multiple arguments.
  -- ARGUMENT...
            Pass all remaining values to the launched app. Only valid for run.
  --console Attach to stdout/stderr of an app launched on a physical device and wait for it to exit.
  --no-code-signing
            Compile without code signing. Not valid for run.
  --skip-build
            For run: install and launch the existing compatible app product.
  --simulator-boot-timeout-seconds COUNT
            Maximum time to wait for simulator boot readiness. Default: 120.
  --full-output, --verbose
            Print complete build output instead of concise progress.

Examples:
  ./build.sh run
  ./build.sh run --ios 26.5
  ./build.sh run --device
  ./build.sh run --device-id 00008150-00110D923412401C
  ./build.sh run --device --console -- -example value
  ./build.sh run --device -- -example value
  ./build.sh run --launch-argument=-example --launch-argument value
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    build|run|clean-intermediates)
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
    --derived-data)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --derived-data requires a path" >&2
        exit 2
      fi
      DERIVED_DATA_PATH="$2"
      DERIVED_DATA_OVERRIDDEN=1
      shift
      ;;
    --cloned-source-packages-dir-path)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --cloned-source-packages-dir-path requires a path" >&2
        exit 2
      fi
      PACKAGE_CACHE_ROOT="$2"
      PACKAGE_CACHE_ROOT_OVERRIDDEN=1
      shift
      ;;
    --xcodebuild-log-dir)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --xcodebuild-log-dir requires a path" >&2
        exit 2
      fi
      XCODEBUILD_LOG_DIR="$2"
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
    --)
      shift
      if [[ $# -eq 0 ]]; then
        echo "error: -- requires at least one launch argument" >&2
        exit 2
      fi
      LAUNCH_ARGUMENTS+=("$@")
      HAS_LAUNCH_ARGUMENTS=1
      break
      ;;
    --no-code-signing)
      CODE_SIGNING_ALLOWED="NO"
      ;;
    --console)
      ATTACH_CONSOLE=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --simulator-boot-timeout-seconds)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --simulator-boot-timeout-seconds requires a positive integer" >&2
        exit 2
      fi
      SIMULATOR_BOOT_TIMEOUT_SECONDS="$2"
      shift
      ;;
    --build-lock-held)
      BUILD_LOCK_HELD=1
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

  if [[ "$ATTACH_CONSOLE" == "1" && ("$ACTION" != "run" || "$USE_DEVICE" != "1") ]]; then
    echo "error: --console is only valid for run with --device or --device-id" >&2
    exit 2
  fi

  if [[ "$ACTION" == "run" && "$CODE_SIGNING_ALLOWED" == "NO" ]]; then
    echo "error: --no-code-signing cannot be used for run" >&2
    exit 2
  fi

  if [[ "$SKIP_BUILD" == "1" && "$ACTION" != "run" ]]; then
    echo "error: --skip-build is only valid for run" >&2
    exit 2
  fi

  if [[ ! "$SIMULATOR_BOOT_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: --simulator-boot-timeout-seconds must be a positive integer" >&2
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

expand_path() {
  local requested_path="$1"
  case "$requested_path" in
    "~") requested_path="$HOME" ;;
    "~/"*) requested_path="$HOME/${requested_path#\~/}" ;;
  esac
  if [[ "$requested_path" != /* ]]; then
    requested_path="$ROOT_DIR/$requested_path"
  fi
  printf '%s\n' "$requested_path"
}

safe_path_component() {
  printf '%s' "$1" | tr -c '[:alnum:]_.-' '-'
}

resolve_toolchain_key() {
  local version_output
  local version
  local build_version
  version_output="$(xcodebuild -version)"
  version="$(awk '/^Xcode / { print $2; exit }' <<< "$version_output")"
  build_version="$(awk '/^Build version / { print $3; exit }' <<< "$version_output")"
  if [[ -z "$version" || -z "$build_version" ]]; then
    echo "error: could not resolve the active Xcode version for cache isolation" >&2
    exit 2
  fi
  printf 'xcode-%s-%s\n' \
    "$(safe_path_component "$version")" \
    "$(safe_path_component "$build_version")"
}

configure_cache_paths() {
  TOOLCHAIN_KEY="$(resolve_toolchain_key)"
  if [[ "$DERIVED_DATA_OVERRIDDEN" == "0" ]]; then
    DERIVED_DATA_PATH="$ROOT_DIR/.build/xcodebuild-derived-data/$TOOLCHAIN_KEY"
  else
    DERIVED_DATA_PATH="$(expand_path "$DERIVED_DATA_PATH")"
  fi
  PACKAGE_CACHE_ROOT="$(expand_path "$PACKAGE_CACHE_ROOT")"
  XCODEBUILD_LOG_DIR="$(expand_path "$XCODEBUILD_LOG_DIR")"
  PACKAGE_GRAPH_KEY="$("$ROOT_DIR/script/package_graph_key.sh")"
  CLONED_SOURCE_PACKAGES_DIR_PATH="$PACKAGE_CACHE_ROOT/$PACKAGE_GRAPH_KEY"

  local module_cache_root="$ROOT_DIR/.build/tool-caches/modules/$TOOLCHAIN_KEY"
  export CLANG_MODULE_CACHE_PATH="$module_cache_root/clang"
  export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache_root/swiftpm"
  mkdir -p \
    "$(dirname "$DERIVED_DATA_PATH")" \
    "$PACKAGE_CACHE_ROOT" \
    "$XCODEBUILD_LOG_DIR" \
    "$CLANG_MODULE_CACHE_PATH" \
    "$SWIFTPM_MODULECACHE_OVERRIDE"
}

acquire_build_lock() {
  if [[ "$BUILD_LOCK_HELD" == "1" ]]; then
    return
  fi

  local reentry_args=()
  case "${ORIGINAL_ARGS[0]:-}" in
    build|run|clean-intermediates)
      reentry_args=(
        "${ORIGINAL_ARGS[0]}"
        --build-lock-held
        "${ORIGINAL_ARGS[@]:1}"
      )
      ;;
    *)
      reentry_args=(--build-lock-held "${ORIGINAL_ARGS[@]}")
      ;;
  esac

  echo "Waiting for BetterTG build lock: $BUILD_LOCK_PATH"
  exec /usr/bin/lockf \
    "$BUILD_LOCK_PATH" \
    "$ROOT_DIR/script/build.sh" \
    "${reentry_args[@]}"
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
  local timestamp
  local log_path
  local command_status
  local formatter_status=0
  local pipeline_status=()
  timestamp="$(date +%Y%m%d-%H%M%S)"
  log_path="$XCODEBUILD_LOG_DIR/${ACTION}-${CONFIGURATION}-${timestamp}-$$-$RANDOM.log"
  LAST_XCODEBUILD_LOG_PATH="$log_path"

  {
    printf 'Command:'
    printf ' %q' "$@"
    printf '\n'
  } > "$log_path"
  echo "Full xcodebuild log: $log_path"

  set +e
  if [[ "$FULL_OUTPUT" == "1" ]]; then
    "$@" 2>&1 | tee -a "$log_path"
    pipeline_status=("${PIPESTATUS[@]}")
  else
    "$@" 2>&1 |
      tee -a "$log_path" |
      "$ROOT_DIR/script/compact_xcodebuild_output.sh" "$log_path"
    pipeline_status=("${PIPESTATUS[@]}")
    formatter_status="${pipeline_status[2]}"
  fi
  set -e
  command_status="${pipeline_status[0]}"

  if [[ "$formatter_status" -ne 0 ]]; then
    echo "warning: compact xcodebuild formatter failed with status $formatter_status" >&2
  fi
  if [[ "$command_status" -ne 0 ]]; then
    echo "error: command failed: $*" >&2
    echo "Last 60 xcodebuild log lines:" >&2
    tail -n 60 "$log_path" >&2
  fi
  return "$command_status"
}

generated_package_resolved_path() {
  printf '%s/BetterTG.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved\n' "$ROOT_DIR"
}

cached_package_resolved_path() {
  printf '%s/.workspace-Package.resolved\n' "$CLONED_SOURCE_PACKAGES_DIR_PATH"
}

package_cache_is_ready() {
  [[ -f "$CLONED_SOURCE_PACKAGES_DIR_PATH/.ready" ]] &&
    [[ -f "$CLONED_SOURCE_PACKAGES_DIR_PATH/workspace-state.json" ]] &&
    [[ -f "$(cached_package_resolved_path)" ]] &&
    {
      [[ -f "$CLONED_SOURCE_PACKAGES_DIR_PATH/checkouts/TDLibKit/Sources/TDLibKit/Generated/Models/Update.swift" ]] ||
        [[ -f "$CLONED_SOURCE_PACKAGES_DIR_PATH/checkouts/tdlibkit/Sources/TDLibKit/Generated/Models/Update.swift" ]]
    }
}

restore_package_resolved() {
  local destination
  local temporary
  destination="$(generated_package_resolved_path)"
  temporary="$destination.tmp.$$"
  mkdir -p "$(dirname "$destination")"
  cp "$(cached_package_resolved_path)" "$temporary"
  mv "$temporary" "$destination"
}

publish_package_cache() {
  local source
  local cached
  source="$(generated_package_resolved_path)"
  cached="$(cached_package_resolved_path)"
  if [[ ! -f "$source" || ! -f "$CLONED_SOURCE_PACKAGES_DIR_PATH/workspace-state.json" ]]; then
    echo "error: Swift package resolution did not produce reusable cache metadata" >&2
    return 1
  fi
  cp "$source" "$cached.tmp.$$"
  mv "$cached.tmp.$$" "$cached"
  touch "$CLONED_SOURCE_PACKAGES_DIR_PATH/.ready"
}

clean_derived_data_intermediates() {
  case "$DERIVED_DATA_PATH" in
    ""|/|"$HOME"|"$ROOT_DIR"|"$ROOT_DIR/.build")
      echo "error: refusing unsafe DerivedData cleanup path: $DERIVED_DATA_PATH" >&2
      return 1
      ;;
  esac

  echo "Cleaning DerivedData intermediates: $DERIVED_DATA_PATH"
  rm -rf \
    "$DERIVED_DATA_PATH/Build/Intermediates.noindex" \
    "$DERIVED_DATA_PATH/CompilationCache.noindex" \
    "$DERIVED_DATA_PATH/Index.noindex" \
    "$DERIVED_DATA_PATH/ModuleCache.noindex" \
    "$DERIVED_DATA_PATH/SDKStatCaches.noindex"
}

migrate_legacy_caches_if_needed() {
  local legacy_derived_data="$ROOT_DIR/.build/xcode"
  local legacy_source_packages="$legacy_derived_data/SourcePackages"
  local current_resolved
  local cache_metadata_rewritten=0
  current_resolved="$(generated_package_resolved_path)"

  if [[ "$PACKAGE_CACHE_ROOT_OVERRIDDEN" == "0" ]] &&
    [[ ! -e "$CLONED_SOURCE_PACKAGES_DIR_PATH" ]] &&
    [[ -f "$legacy_source_packages/workspace-state.json" ]]; then
    echo "Adopting existing Swift packages without downloading: $CLONED_SOURCE_PACKAGES_DIR_PATH"
    mv "$legacy_source_packages" "$CLONED_SOURCE_PACKAGES_DIR_PATH"
    if [[ -f "$current_resolved" ]]; then
      cp "$current_resolved" "$(cached_package_resolved_path)"
      touch "$CLONED_SOURCE_PACKAGES_DIR_PATH/.ready"
    fi
  fi

  local workspace_state="$CLONED_SOURCE_PACKAGES_DIR_PATH/workspace-state.json"
  if [[ -f "$workspace_state" ]] &&
    grep -Fq "$legacy_source_packages" "$workspace_state"; then
    echo "Updating migrated Swift package artifact paths..."
    jq \
      --arg oldRoot "$legacy_source_packages" \
      --arg newRoot "$CLONED_SOURCE_PACKAGES_DIR_PATH" \
      --argjson oldRootLength "${#legacy_source_packages}" '
        .object.artifacts |= map(
          if ((.path // "") | startswith($oldRoot)) then
            .path = ($newRoot + (.path[$oldRootLength:]))
          else
            .
          end
        )
      ' "$workspace_state" > "$workspace_state.tmp.$$"
    mv "$workspace_state.tmp.$$" "$workspace_state"
    cache_metadata_rewritten=1
  fi

  if [[ "$DERIVED_DATA_OVERRIDDEN" == "0" ]] &&
    [[ ! -e "$DERIVED_DATA_PATH" ]] &&
    [[ -d "$legacy_derived_data" ]]; then
    echo "Adopting existing DerivedData for $TOOLCHAIN_KEY: $DERIVED_DATA_PATH"
    mv "$legacy_derived_data" "$DERIVED_DATA_PATH"
  fi

  mkdir -p "$DERIVED_DATA_PATH" "$CLONED_SOURCE_PACKAGES_DIR_PATH"
  if [[ "$DERIVED_DATA_OVERRIDDEN" == "0" ]] &&
    { [[ ! -f "$DERIVED_DATA_PATH/.bettertg-cache-layout-v1" ]] ||
      [[ "$cache_metadata_rewritten" == "1" ]]; }; then
    echo "Removing path-sensitive intermediates while preserving products and Swift packages..."
    clean_derived_data_intermediates
    touch "$DERIVED_DATA_PATH/.bettertg-cache-layout-v1"
  fi
}

resolve_swift_packages() {
  local resolved_path
  resolved_path="$(generated_package_resolved_path)"
  rm -f "$resolved_path"
  run_xcodebuild xcodebuild \
    -resolvePackageDependencies \
    -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR_PATH" \
    -packageAuthorizationProvider netrc \
    -scmProvider system \
    -skipPackagePluginValidation \
    -skipMacroValidation
  publish_package_cache
}

prepare_swift_packages() {
  if package_cache_is_ready; then
    echo "Reusing Swift package graph ${PACKAGE_GRAPH_KEY:0:12}: $CLONED_SOURCE_PACKAGES_DIR_PATH"
    restore_package_resolved
    return
  fi

  echo "Resolving Swift package graph ${PACKAGE_GRAPH_KEY:0:12}..."
  resolve_swift_packages
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
    local launch_options=(
      --device "$DEVICE_ID"
      --terminate-existing
      --activate
    )
    if [[ "$ATTACH_CONSOLE" == "1" ]]; then
      launch_options+=(--console)
    fi
    xcrun devicectl device process launch "${launch_options[@]}" -- "$BUNDLE_ID" "${LAUNCH_ARGUMENTS[@]}"
  else
    local launch_options=(
      --device "$DEVICE_ID"
      --terminate-existing
      --activate
    )
    if [[ "$ATTACH_CONSOLE" == "1" ]]; then
      launch_options+=(--console)
    fi
    xcrun devicectl device process launch "${launch_options[@]}" "$BUNDLE_ID"
  fi
}

launch_on_simulator() {
  echo "Booting simulator and waiting for readiness: $SIMULATOR_ID"
  xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
  "$ROOT_DIR/script/simulator_boot_status.sh" \
    --simulator-id "$SIMULATOR_ID" \
    --timeout-seconds "$SIMULATOR_BOOT_TIMEOUT_SECONDS"
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
require_command lockf
acquire_build_lock
configure_xcode
configure_cache_paths
migrate_legacy_caches_if_needed

if [[ "$ACTION" == "clean-intermediates" ]]; then
  clean_derived_data_intermediates
  echo "Preserved build products and Swift package cache."
  exit 0
fi

if [[ "$USE_DEVICE" == "1" ]]; then
  echo "Finding a connected iPhone..."
  DEVICE_ID="$(resolve_connected_iphone_id "$DEVICE_ID")"
  destination="platform=iOS,id=$DEVICE_ID"
  product_platform="iphoneos"
else
  if [[ -z "$SIMULATOR_ID" ]]; then
    SIMULATOR_ID="$(simulator_id)"
  fi
  destination="platform=iOS Simulator,id=$SIMULATOR_ID"
  product_platform="iphonesimulator"
fi

if [[ "$SKIP_BUILD" == "0" ]]; then
  echo "Generating the Xcode project..."
  run_with_filtered_output "$ROOT_DIR/script/generate_xcodeproj.sh"

  prepare_swift_packages

  echo "Updating generated TDLib models..."
  run_with_filtered_output python3 "$ROOT_DIR/td.py" \
    --skip-resolve \
    --cloned-source-packages-dir-path "$CLONED_SOURCE_PACKAGES_DIR_PATH"

  xcodebuild_args=(
    -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR_PATH"
    -destination "$destination"
    -packageAuthorizationProvider netrc
    -scmProvider system
    -skipPackagePluginValidation
    -skipMacroValidation
    -disableAutomaticPackageResolution
    "CLANG_MODULE_CACHE_PATH=$CLANG_MODULE_CACHE_PATH"
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
else
  echo "Skipping build and reusing the existing $CONFIGURATION app product."
fi

if [[ "$ACTION" == "build" ]]; then
  exit 0
fi

APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-$product_platform/$APP_NAME.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  if [[ "$SKIP_BUILD" == "1" ]]; then
    echo "Run the same command once without --skip-build." >&2
  fi
  exit 1
fi

if [[ "$USE_DEVICE" == "1" ]]; then
  launch_on_device
else
  launch_on_simulator
fi
