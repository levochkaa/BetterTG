#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/project.yml"
LOCAL_PACKAGE_MANIFEST="$ROOT_DIR/Packages/TDLibKitDynamic/Package.swift"

package_section="$(
  awk '
    /^packages:[[:space:]]*$/ {
      capture = 1
    }
    capture && !/^packages:[[:space:]]*$/ && /^[^[:space:]#][^:]*:/ {
      exit
    }
    capture {
      print
    }
  ' "$PROJECT_FILE"
)"

if [[ -z "$package_section" ]]; then
  echo "error: could not find the top-level packages section in $PROJECT_FILE" >&2
  exit 1
fi

{
  printf '%s\n' "bettertg-package-graph-v1"
  xcodebuild -version
  printf '%s\n' "$package_section"
  if [[ -f "$LOCAL_PACKAGE_MANIFEST" ]]; then
    printf '%s\n' "TDLibKitDynamic Package.swift"
    cat "$LOCAL_PACKAGE_MANIFEST"
  fi
} | shasum -a 256 | awk '{ print $1 }'
