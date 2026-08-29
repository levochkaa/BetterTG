#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/project.yml"

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
} | shasum -a 256 | awk '{ print $1 }'
