# BetterTG Agent Instructions

> Sync note: keep `AGENTS.md` and `CLAUDE.md` in sync. Any workflow or tooling change made in one file must be copied to the other in the same change.

## Build And Test

- Do not use XcodeBuildMCP or other MCP tooling for BetterTG build, test, run, or simulator validation unless the user explicitly asks for it.
- Build through the repo script: `./script/build.sh` or the root wrapper `./build.sh`.
- Test through the repo script: `./script/test.sh` or the root wrapper `./test.sh`.
- `script/test.sh` currently runs the simulator build validation because the project has no dedicated test target.
- The scripts own Xcode environment setup, project generation, TDLib model generation, package resolution, derived data location, and simulator selection.
- Use `SIMULATOR_NAME="..."` or `SIMULATOR_ID="..."` only when the default simulator needs to be overridden.

## Project Notes

- Main project: `BetterTG.xcodeproj`.
- Main scheme: `BetterTG`.
- Prefer narrow, codebase-consistent SwiftUI/UIKit changes and preserve unrelated local edits.
