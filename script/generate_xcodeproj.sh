#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
PROJECT_PATH="$ROOT_DIR/BetterTG.xcodeproj"

"$ROOT_DIR/script/prepare_worktree.sh"

if [[ ! -f "$PROJECT_SPEC" ]]; then
  echo "error: missing project spec at $PROJECT_SPEC" >&2
  exit 1
fi

echo "Generating BetterTG.xcodeproj from project.yml"
if [[ -d "$PROJECT_PATH" ]]; then
  chmod -R u+w "$PROJECT_PATH"
fi
cd "$ROOT_DIR"
# Xcode 27.2 expands an asset catalog that holds a membership exception and fails on its Contents.json files; the
# exclude in project.yml makes one of any Finder file inside it.
find "$ROOT_DIR/BetterTG/Assets.xcassets" -name .DS_Store -delete
xcodegen generate --spec "$PROJECT_SPEC"
