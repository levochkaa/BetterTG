#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/device.sh"
ORIGINAL_ARGS=("$@")

PROJECT_NAME="BetterTG"
APP_NAME="BetterTG"
# Read from the built app, because setup.sh lets a fork sign with its own bundle ID.
BUNDLE_ID=""
SCHEME="BetterTG"
DEFAULT_XCODE_PATH="/Applications/Xcode-27.1.0.app"
XCODE_PATH="$DEFAULT_XCODE_PATH"
CONFIGURATION="Debug"
CONFIGURATION_SET=0
ARCHIVE_PATH=""
BUILD_NUMBER=""
AUTHENTICATION_KEY_PATH=""
AUTHENTICATION_KEY_ID=""
AUTHENTICATION_KEY_ISSUER_ID=""
DERIVED_DATA_PATH=""
DERIVED_DATA_OVERRIDDEN=0
PACKAGE_CACHE_ROOT="$HOME/Library/Developer/Xcode/PackageGraphCaches"
PACKAGE_CACHE_ROOT_OVERRIDDEN=0
PACKAGE_GRAPH_KEY=""
CLONED_SOURCE_PACKAGES_DIR_PATH=""
TOOLCHAIN_KEY=""
BUILD_LOCK_PATH="/tmp/bettertg-build.lock"
BUILD_LOCK_HELD=0
BUILD_ONLY=0
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
MINIMUM_FREE_DISK_GB=5
CLEAN_DRY_RUN=0
CACHE_RECENT_GRACE_MINUTES=15
# Compiling builds from every worktree share one compilation cache per Xcode build.
COMPILATION_CACHE_ROOT="$HOME/Library/Caches/BetterTG/CompilationCache"
# Marks a Swift package graph cache as BetterTG's; the shared root also holds other projects' caches.
PACKAGE_GRAPH_MARKER=".bettertg-package-graph"
DERIVED_DATA_USE_STAMP=".bettertg-last-used"

usage() {
  cat <<'EOF'
Usage: ./build.sh [build|run|archive|clean-intermediates|clean-cache] [options]

Commands:
  build     Build BetterTG (default).
  run       Build, install, and launch BetterTG.
  archive   Archive BetterTG for distribution to --archive-path. Default configuration: Release.
  clean-intermediates
            Remove compilation, index, module, and SDK-stat intermediates while preserving products and Swift packages.
  clean-cache
            Remove caches no BetterTG worktree uses: DerivedData, module and compilation caches of other Xcode
            versions, other worktrees' DerivedData unused for --cache-recent-grace-minutes, and BetterTG Swift
            package graph caches other than the current one. Other projects' package caches are left alone.

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
            Xcode .app or Developer directory. Default: /Applications/Xcode-27.1.0.app.
  --derived-data PATH
            DerivedData path. Default: .build/xcodebuild-derived-data/<Xcode version>.
  --cloned-source-packages-dir-path PATH
            Root for graph-keyed Swift package caches.
  --xcodebuild-log-dir PATH
            Full xcodebuild log directory. Default: .build/logs/xcodebuild.
  --configuration Debug|Release, --debug, --release
            Build configuration. Default: Debug, Release for archive.
  --archive-path PATH
            For archive: where to write the .xcarchive.
  --build-number NUMBER
            For archive: the archive's CURRENT_PROJECT_VERSION.
  --authentication-key-path PATH, --authentication-key-id ID, --authentication-key-issuer-id ID
            For archive: an App Store Connect API key that lets Xcode manage signing without a signed-in account.
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
  --minimum-free-disk-gb COUNT
            Fail a compiling build below this much free disk, deleting nothing. 0 disables the check. Default: 5.
  --dry-run
            For clean-cache and clean-intermediates: list what would be removed, with sizes, and remove nothing.
  --cache-recent-grace-minutes COUNT
            For clean-cache: keep another worktree's DerivedData and a package graph used this recently. Default: 15.

Examples:
  ./build.sh run
  ./build.sh run --ios 26.5
  ./build.sh run --device
  ./build.sh run --device-id 00008150-00110D923412401C
  ./build.sh run --device --console -- -example value
  ./build.sh run --device -- -example value
  ./build.sh run --launch-argument=-example --launch-argument value
  ./build.sh archive --archive-path .build/archives/BetterTG.xcarchive --build-number 42
  ./build.sh clean-cache --dry-run
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    build|run|archive|clean-intermediates|clean-cache)
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
        Debug|debug) CONFIGURATION="Debug"; CONFIGURATION_SET=1 ;;
        Release|release) CONFIGURATION="Release"; CONFIGURATION_SET=1 ;;
        *)
          echo "error: unsupported configuration '$2' (expected Debug or Release)" >&2
          exit 2
          ;;
      esac
      shift
      ;;
    --debug)
      CONFIGURATION="Debug"
      CONFIGURATION_SET=1
      ;;
    --release)
      CONFIGURATION="Release"
      CONFIGURATION_SET=1
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
    --archive-path|--build-number|--authentication-key-path|--authentication-key-id|--authentication-key-issuer-id)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: $1 requires a value" >&2
        exit 2
      fi
      case "$1" in
        --archive-path)
          ARCHIVE_PATH="$2"
          [[ "$ARCHIVE_PATH" == /* ]] || ARCHIVE_PATH="$PWD/$ARCHIVE_PATH"
          ;;
        --build-number) BUILD_NUMBER="$2" ;;
        --authentication-key-path)
          AUTHENTICATION_KEY_PATH="$2"
          [[ "$AUTHENTICATION_KEY_PATH" == /* ]] || AUTHENTICATION_KEY_PATH="$PWD/$AUTHENTICATION_KEY_PATH"
          ;;
        --authentication-key-id) AUTHENTICATION_KEY_ID="$2" ;;
        --authentication-key-issuer-id) AUTHENTICATION_KEY_ISSUER_ID="$2" ;;
      esac
      shift
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
    --build-only)
      BUILD_ONLY=1
      ;;
    --full-output|--verbose)
      FULL_OUTPUT=1
      ;;
    --minimum-free-disk-gb)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --minimum-free-disk-gb requires a non-negative integer" >&2
        exit 2
      fi
      MINIMUM_FREE_DISK_GB="$2"
      shift
      ;;
    --dry-run)
      CLEAN_DRY_RUN=1
      ;;
    --cache-recent-grace-minutes)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --cache-recent-grace-minutes requires a non-negative integer" >&2
        exit 2
      fi
      CACHE_RECENT_GRACE_MINUTES="$2"
      shift
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
  if [[ "$ACTION" == "archive" && "$CONFIGURATION_SET" == "0" ]]; then
    CONFIGURATION="Release"
  fi

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

  if [[ "$ACTION" == "archive" ]]; then
    if [[ -z "$ARCHIVE_PATH" ]]; then
      echo "error: archive requires --archive-path" >&2
      exit 2
    fi
    if [[ "$USE_DEVICE" == "1" || -n "$SIMULATOR_ID" || "$CODE_SIGNING_ALLOWED" == "NO" ]]; then
      echo "error: archive builds for any iPhone and signs; drop --device, --simulator-id and --no-code-signing" >&2
      exit 2
    fi
    if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
      echo "error: --build-number must be a positive integer" >&2
      exit 2
    fi
    local authentication_count=0
    [[ -z "$AUTHENTICATION_KEY_PATH" ]] || authentication_count=$((authentication_count + 1))
    [[ -z "$AUTHENTICATION_KEY_ID" ]] || authentication_count=$((authentication_count + 1))
    [[ -z "$AUTHENTICATION_KEY_ISSUER_ID" ]] || authentication_count=$((authentication_count + 1))
    if [[ "$authentication_count" != "0" && "$authentication_count" != "3" ]]; then
      echo "error: pass all of --authentication-key-path, --authentication-key-id and --authentication-key-issuer-id" >&2
      exit 2
    fi
  elif [[ -n "$ARCHIVE_PATH$BUILD_NUMBER$AUTHENTICATION_KEY_PATH$AUTHENTICATION_KEY_ID$AUTHENTICATION_KEY_ISSUER_ID" ]]; then
    echo "error: --archive-path, --build-number and --authentication-key-* are only valid for archive" >&2
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

  if [[ ! "$MINIMUM_FREE_DISK_GB" =~ ^[0-9]+$ ]]; then
    echo "error: --minimum-free-disk-gb must be a non-negative integer" >&2
    exit 2
  fi

  if [[ ! "$CACHE_RECENT_GRACE_MINUTES" =~ ^[0-9]+$ ]]; then
    echo "error: --cache-recent-grace-minutes must be a non-negative integer" >&2
    exit 2
  fi

  if [[ "$CLEAN_DRY_RUN" == "1" && "$ACTION" != "clean-cache" && "$ACTION" != "clean-intermediates" ]]; then
    echo "error: --dry-run is only valid for clean-cache and clean-intermediates" >&2
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

  if [[ "$ACTION" == "run" && "$SKIP_BUILD" == "1" ]]; then
    return
  fi

  local reentry_args=()
  case "${ORIGINAL_ARGS[0]:-}" in
    run)
      reentry_args=(
        run
        --build-lock-held
        --build-only
        "${ORIGINAL_ARGS[@]:1}"
      )
      ;;
    build|archive|clean-intermediates|clean-cache)
      reentry_args=(
        "${ORIGINAL_ARGS[0]}"
        --build-lock-held
        "${ORIGINAL_ARGS[@]:1}"
      )
      ;;
    *)
      if [[ "$ACTION" == "run" ]]; then
        reentry_args=(--build-lock-held --build-only "${ORIGINAL_ARGS[@]}")
      else
        reentry_args=(--build-lock-held "${ORIGINAL_ARGS[@]}")
      fi
      ;;
  esac

  echo "Waiting for BetterTG build lock: $BUILD_LOCK_PATH"
  if [[ "$ACTION" == "run" ]]; then
    /usr/bin/lockf \
      "$BUILD_LOCK_PATH" \
      "$ROOT_DIR/script/build.sh" \
      "${reentry_args[@]}"
    SKIP_BUILD=1
    return
  fi
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

  grep -Ein "error:|warning:" || true
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
    [[ -f "$CLONED_SOURCE_PACKAGES_DIR_PATH/workspace-state.json" ]]
}

tdlibkit_schema_path() {
  local checkout_name
  local candidate
  for checkout_name in TDLibKit tdlibkit; do
    candidate="$CLONED_SOURCE_PACKAGES_DIR_PATH/checkouts/$checkout_name/Sources/TDLibKitNative/Generated/SchemaViews.swift"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "error: resolved TDLibKit checkout does not contain SchemaViews.swift" >&2
  return 1
}

restore_package_resolved() {
  local destination
  local temporary
  destination="$(generated_package_resolved_path)"
  [[ -f "$(cached_package_resolved_path)" ]] || return 0
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
  if [[ ! -f "$CLONED_SOURCE_PACKAGES_DIR_PATH/workspace-state.json" ]]; then
    echo "error: Swift package resolution did not produce reusable cache metadata" >&2
    return 1
  fi
  if [[ -f "$source" ]]; then
    cp "$source" "$cached.tmp.$$"
    mv "$cached.tmp.$$" "$cached"
  else
    rm -f "$cached"
  fi
  touch "$CLONED_SOURCE_PACKAGES_DIR_PATH/.ready"
}

clean_derived_data_intermediates() {
  case "$DERIVED_DATA_PATH" in
    ""|/|"$HOME"|"$ROOT_DIR"|"$ROOT_DIR/.build")
      echo "error: refusing unsafe DerivedData cleanup path: $DERIVED_DATA_PATH" >&2
      return 1
      ;;
  esac

  local intermediates=(
    "$DERIVED_DATA_PATH/Build/Intermediates.noindex"
    "$DERIVED_DATA_PATH/CompilationCache.noindex"
    "$DERIVED_DATA_PATH/Index.noindex"
    "$DERIVED_DATA_PATH/ModuleCache.noindex"
    "$DERIVED_DATA_PATH/SDKStatCaches.noindex"
  )
  if [[ "$CLEAN_DRY_RUN" == "1" ]]; then
    echo "Would clean DerivedData intermediates: $DERIVED_DATA_PATH"
    report_removal_candidates "${intermediates[@]}"
    return
  fi
  echo "Cleaning DerivedData intermediates: $DERIVED_DATA_PATH"
  rm -rf "${intermediates[@]}"
}

# Prints each existing path with its size, then the total.
report_removal_candidates() {
  local total_kb=0 path size_kb
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    size_kb="$(du -sk "$path" 2>/dev/null | awk '{ print $1 }')"
    size_kb="${size_kb:-0}"
    total_kb=$((total_kb + size_kb))
    printf '  %8s  %s\n' "$(human_size_kb "$size_kb")" "$path"
  done
  printf '  %8s  total\n' "$(human_size_kb "$total_kb")"
}

human_size_kb() {
  awk -v kb="$1" 'BEGIN {
    if (kb >= 1048576) printf "%.1fG", kb / 1048576
    else if (kb >= 1024) printf "%.0fM", kb / 1024
    else printf "%dK", kb
  }'
}

# Minutes since a cache was last used, from its use stamp or the newest of the given files.
minutes_since_use() {
  local newest=0 path mtime
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    mtime="$(stat -f %m "$path" 2>/dev/null || echo 0)"
    [[ "$mtime" -gt "$newest" ]] && newest="$mtime"
  done
  if [[ "$newest" == "0" ]]; then
    echo 999999
    return
  fi
  echo $((($(date +%s) - newest) / 60))
}

# Builds hold the machine-wide build lock, so nothing removed here is in use: clean-cache takes the same lock.
clean_cache() {
  local candidates=() worktree entry key
  while IFS= read -r worktree; do
    [[ -d "$worktree/.build" ]] || continue
    for entry in "$worktree/.build/xcodebuild-derived-data"/* "$worktree/.build/tool-caches/modules"/*; do
      [[ -d "$entry" ]] || continue
      key="$(basename "$entry")"
      if [[ "$key" != "$TOOLCHAIN_KEY" ]]; then
        candidates+=("$entry")
      elif [[ "$worktree" != "$ROOT_DIR" && "$entry" == */xcodebuild-derived-data/* ]] &&
        [[ "$(minutes_since_use "$entry/$DERIVED_DATA_USE_STAMP" "$entry/info.plist")" -ge "$CACHE_RECENT_GRACE_MINUTES" ]]; then
        candidates+=("$entry")
      fi
    done
  done < <(git -C "$ROOT_DIR" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')

  for entry in "$COMPILATION_CACHE_ROOT"/*; do
    [[ -d "$entry" && "$(basename "$entry")" != "$TOOLCHAIN_KEY" ]] && candidates+=("$entry")
  done

  for entry in "$PACKAGE_CACHE_ROOT"/*; do
    [[ -d "$entry" && "$entry" != "$CLONED_SOURCE_PACKAGES_DIR_PATH" ]] || continue
    # Caches prepared before the marker existed are recognised by their TDLibKit checkout.
    [[ -f "$entry/$PACKAGE_GRAPH_MARKER" || -d "$entry/checkouts/TDLibKit" ]] || continue
    if [[ "$(minutes_since_use "$entry/$PACKAGE_GRAPH_MARKER" "$entry/.ready")" -ge "$CACHE_RECENT_GRACE_MINUTES" ]]; then
      candidates+=("$entry")
    fi
  done

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "No unused BetterTG caches."
    return
  fi
  if [[ "$CLEAN_DRY_RUN" == "1" ]]; then
    echo "Would remove unused BetterTG caches:"
    report_removal_candidates "${candidates[@]}"
    return
  fi
  echo "Removing unused BetterTG caches:"
  report_removal_candidates "${candidates[@]}"
  for entry in "${candidates[@]}"; do
    case "$entry" in
      */.build/xcodebuild-derived-data/?*|*/.build/tool-caches/modules/?*|"$COMPILATION_CACHE_ROOT"/?*|"$PACKAGE_CACHE_ROOT"/?*)
        rm -rf "$entry"
        ;;
      *)
        echo "error: refusing unexpected cache path: $entry" >&2
        return 1
        ;;
    esac
  done
}

# Fails before compiling below the free-space floor; nothing is deleted.
disk_space_preflight() {
  [[ "$MINIMUM_FREE_DISK_GB" != "0" ]] || return 0
  local available_kb minimum_kb=$((MINIMUM_FREE_DISK_GB * 1024 * 1024))
  available_kb="$(df -Pk "$ROOT_DIR" | awk 'NR == 2 { print $4 }')"
  if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
    echo "error: could not determine free disk space for $ROOT_DIR" >&2
    exit 66
  fi
  if [[ "$available_kb" -lt "$minimum_kb" ]]; then
    echo "error: $(human_size_kb "$available_kb") free at $ROOT_DIR; building needs ${MINIMUM_FREE_DISK_GB}G." >&2
    echo "Preview cleanup with ./build.sh clean-cache --dry-run or ./build.sh clean-intermediates --dry-run. Pass --minimum-free-disk-gb 0 only when the space is known to be enough." >&2
    exit 73
  fi
}

# Local builds share one compilation cache across worktrees for C, C++ and Objective-C (Swift caching is off in
# project.yml). Prefix mapping records the worktree path, which also holds its DerivedData and module caches, as
# /^root in cache keys and debug info, so a new worktree reuses what another one compiled. LLDB then needs
# `settings set target.source-map /^root <worktree>` for full-path breakpoints and source listing in that code.
append_shared_compilation_cache_args() {
  # Xcode splits list settings on whitespace, so such a worktree path cannot be mapped.
  [[ "$ROOT_DIR" != *[[:space:]]* ]] || return 0
  xcodebuild_args+=(
    "COMPILATION_CACHE_CAS_PATH=$COMPILATION_CACHE_ROOT/$TOOLCHAIN_KEY"
    "COMPILATION_CACHE_LIMIT_SIZE=20G"
    "CLANG_ENABLE_PREFIX_MAPPING=YES"
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES"
    "CLANG_OTHER_PREFIX_MAPPINGS=$ROOT_DIR=/^root"
  )
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
  # Headless: the Simulator is watched through T3 Code's Device panel, idb or XcodeBuildMCP, never Simulator.app.
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
  [[ "$CLEAN_DRY_RUN" == "1" ]] || echo "Preserved build products and Swift package cache."
  exit 0
fi

if [[ "$ACTION" == "clean-cache" ]]; then
  clean_cache
  exit 0
fi

if [[ "$ACTION" == "archive" ]]; then
  destination="generic/platform=iOS"
  product_platform="iphoneos"
elif [[ "$USE_DEVICE" == "1" ]]; then
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
  disk_space_preflight
  echo "Generating the Xcode project..."
  run_with_filtered_output "$ROOT_DIR/script/generate_xcodeproj.sh"

  prepare_swift_packages
  touch "$CLONED_SOURCE_PACKAGES_DIR_PATH/$PACKAGE_GRAPH_MARKER"

  echo "Updating generated TDLib models..."
  TDLIBKIT_SCHEMA_PATH="$(tdlibkit_schema_path)"
  run_with_filtered_output python3 "$ROOT_DIR/script/generate_tdlib_native_aliases.py" \
    --schema "$TDLIBKIT_SCHEMA_PATH"
  run_with_filtered_output python3 "$ROOT_DIR/script/generate_tdlib_client_compat.py" \
    --schema "$TDLIBKIT_SCHEMA_PATH"
  run_with_filtered_output python3 "$ROOT_DIR/script/generate_tdlib_initializer_compat.py" \
    --schema "$TDLIBKIT_SCHEMA_PATH"
  run_with_filtered_output python3 "$ROOT_DIR/script/generate_tdlib_value_equality.py" \
    --schema "$TDLIBKIT_SCHEMA_PATH"
  run_with_filtered_output python3 "$ROOT_DIR/script/td.py" \
    --skip-resolve \
    --cloned-source-packages-dir-path "$CLONED_SOURCE_PACKAGES_DIR_PATH"
  run_with_filtered_output swiftformat \
    --config "$ROOT_DIR/.swiftformat" \
    --cache ignore \
    "$ROOT_DIR/BetterTG/Shared/TDNativeAliases.swift" \
    "$ROOT_DIR/BetterTG/Shared/TDClient+Generated.swift" \
    "$ROOT_DIR/BetterTG/Shared/TDNativeInitializers+Generated.swift" \
    "$ROOT_DIR/BetterTG/Extensions/Td/TDNativeValueEquality+Generated.swift" \
    "$ROOT_DIR/BetterTG/Extensions/Td/Td+Generated.swift"

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
  append_shared_compilation_cache_args
  touch "$DERIVED_DATA_PATH/$DERIVED_DATA_USE_STAMP"

  if [[ "$CONFIGURATION" == "Debug" ]]; then
    # TDLibKit's generated C++ schema switch reserves a large stack frame at
    # -O0. Nested draft/rich-message clones can overflow a Swift worker stack.
    # -O1 reuses those temporary slots; Swift still uses Debug's -Onone.
    xcodebuild_args+=("GCC_OPTIMIZATION_LEVEL=1")
  fi

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

  xcodebuild_action="build"
  if [[ "$ACTION" == "archive" ]]; then
    xcodebuild_action="archive"
    xcodebuild_args+=(-allowProvisioningUpdates -archivePath "$ARCHIVE_PATH")
    if [[ -n "$AUTHENTICATION_KEY_PATH" ]]; then
      xcodebuild_args+=(
        -authenticationKeyPath "$AUTHENTICATION_KEY_PATH"
        -authenticationKeyID "$AUTHENTICATION_KEY_ID"
        -authenticationKeyIssuerID "$AUTHENTICATION_KEY_ISSUER_ID"
      )
    fi
    if [[ -n "$BUILD_NUMBER" ]]; then
      xcodebuild_args+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
    fi
  fi

  if [[ "$ACTION" == "archive" ]]; then
    echo "Archiving $APP_NAME to $ARCHIVE_PATH..."
  else
    echo "Building $APP_NAME for $destination..."
  fi
  build_started_at=$SECONDS
  run_xcodebuild xcodebuild "${xcodebuild_args[@]}" "$xcodebuild_action"
  if [[ "$ACTION" == "archive" ]]; then
    echo "$APP_NAME archived in $((SECONDS - build_started_at))s."
  else
    echo "$APP_NAME built in $((SECONDS - build_started_at))s."
  fi
else
  echo "Skipping build and reusing the existing $CONFIGURATION app product."
fi

if [[ "$BUILD_ONLY" == "1" || "$ACTION" == "build" || "$ACTION" == "archive" ]]; then
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
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"

if [[ "$USE_DEVICE" == "1" ]]; then
  launch_on_device
else
  launch_on_simulator
fi
