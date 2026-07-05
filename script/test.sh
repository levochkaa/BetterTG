#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# BetterTG currently has no test target. Keep the Test action meaningful by
# running the same simulator build validation that CI would need before tests.
"$ROOT_DIR/script/build.sh" "$@"
