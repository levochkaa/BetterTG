#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SECRET_RELATIVE_PATH="BetterTG/Secret/Secret.swift"
LOCAL_CONFIG_RELATIVE_PATH="Configuration/Local.xcconfig"
# The App Store Connect API key of the fastlane lanes.
API_KEY_RELATIVE_PATH="fastlane/api_key.json"

primary_root() {
  local common_git_dir
  common_git_dir="$(git -C "$ROOT_DIR" rev-parse --path-format=absolute --git-common-dir)"
  if [[ "$(basename "$common_git_dir")" != ".git" ]]; then
    echo "error: cannot locate the primary BetterTG checkout from $common_git_dir" >&2
    exit 1
  fi
  (cd "$(dirname "$common_git_dir")" && pwd -P)
}

# Copies an ignored setup.sh output from the primary checkout into a new worktree.
copy_from_primary() {
  local relative_path="$1" required="$2"
  local destination="$ROOT_DIR/$relative_path"

  if [[ -f "$destination" ]]; then
    echo "$relative_path is already available"
    return 0
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    echo "error: $destination exists but is not a regular file" >&2
    exit 1
  fi

  local primary source
  primary="$(primary_root)"
  source="$primary/$relative_path"
  if [[ ! -f "$source" ]]; then
    if [[ "$required" == "1" ]]; then
      if [[ "$primary" == "$ROOT_DIR" ]]; then
        echo "error: missing $relative_path. Run ./setup.sh first." >&2
      else
        echo "error: missing $relative_path in the primary checkout at $primary. Run ./setup.sh there first." >&2
      fi
      exit 1
    fi
    return 0
  fi

  mkdir -p "$(dirname "$destination")"
  install -m 600 "$source" "$destination"
  echo "Prepared $relative_path from the primary checkout"
}

copy_from_primary "$SECRET_RELATIVE_PATH" 1
copy_from_primary "$LOCAL_CONFIG_RELATIVE_PATH" 0
copy_from_primary "$API_KEY_RELATIVE_PATH" 0
