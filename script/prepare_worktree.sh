#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_RELATIVE_PATH="BetterTG/Secret/Secret.swift"
DESTINATION_PATH="$ROOT_DIR/$SECRET_RELATIVE_PATH"

if [[ -f "$DESTINATION_PATH" ]]; then
  echo "$SECRET_RELATIVE_PATH is already available"
  exit 0
fi

if [[ -e "$DESTINATION_PATH" || -L "$DESTINATION_PATH" ]]; then
  echo "error: $DESTINATION_PATH exists but is not a regular file" >&2
  exit 1
fi

COMMON_GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --path-format=absolute --git-common-dir)"
if [[ "$(basename "$COMMON_GIT_DIR")" != ".git" ]]; then
  echo "error: cannot locate the primary BetterTG checkout from $COMMON_GIT_DIR" >&2
  exit 1
fi

PRIMARY_ROOT="$(dirname "$COMMON_GIT_DIR")"
SOURCE_PATH="$PRIMARY_ROOT/$SECRET_RELATIVE_PATH"

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "error: missing $SECRET_RELATIVE_PATH in the primary checkout at $PRIMARY_ROOT" >&2
  echo "Generate it there first by following README.md step 3." >&2
  exit 1
fi

mkdir -p "$(dirname "$DESTINATION_PATH")"
install -m 600 "$SOURCE_PATH" "$DESTINATION_PATH"
echo "Prepared $SECRET_RELATIVE_PATH from the primary checkout"
