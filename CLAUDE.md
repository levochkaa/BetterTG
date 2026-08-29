# BetterTG Agent Instructions

> Sync note: keep `AGENTS.md` and `CLAUDE.md` in sync. Any workflow or tooling change made in one file must be copied to the other in the same change.

## Build And Test

- Do not use XcodeBuildMCP or other MCP tooling for BetterTG build, test, run, or simulator validation unless the user explicitly asks for it.
- Build through the root multiplexer: `./build.sh build` (or `./build.sh`, which defaults to build).
- Run through the root multiplexer: `./build.sh run`. BetterTG currently has no dedicated test target, so build is the repository-level validation.
- The build script owns Xcode environment setup, project generation, TDLib model generation, package resolution, derived data location, and simulator selection.
- Use `SIMULATOR_OS="..."`, `SIMULATOR_NAME="..."`, or `SIMULATOR_ID="..."` only when the default simulator needs to be overridden.
- Use `./build.sh build --device` to build for the available paired physical iPhone and `./build.sh run --device` to build, install, and launch on it. Device builds use Xcode automatic provisioning. Set `DEVICE_ID="..."` only when a specific physical iPhone must be selected.
- Use `RUN_ARGUMENTS="..." ./build.sh run` when an automated launch smoke needs app arguments; do not bypass `build.sh` with a direct simulator launch.
- Do not close or shut down a booted Simulator when finishing a task. Leave it running for the user unless the user explicitly asks to close or shut it down.

## Project Notes

- Main project: `BetterTG.xcodeproj`.
- Main scheme: `BetterTG`.
- Prefer narrow, codebase-consistent UIKit changes and preserve unrelated local edits.

## Git Workflow

- Commit all agent-authored changes before handing the task back to the user, unless the user explicitly asks to leave changes uncommitted.
- For a large task, commit after every coherent, verified implementation stage. Do not wait until the end and put the entire large task into one oversized commit.
- Keep every commit focused and stage only the files or hunks that belong to that stage; never include unrelated user changes.
- Name commits as `<type>(<scope>): <imperative summary>`, with `feature`, `fix`, or `tech` as the type and a concise lowercase scope.
- Keep the summary lowercase, imperative, and specific to the delivered behavior or technical change.
- Add `Co-authored-by: Codex <noreply@openai.com>` to every agent-authored commit.

## UI Implementation

- Implement all application UI in UIKit. Do not introduce SwiftUI, `UIHostingController`, `UIViewRepresentable`, `UIViewControllerRepresentable`, or other SwiftUI-only UI and layout code.
- Keep UI implementations UIKit-native, using `UIViewController`, `UIView`, `UITableView` or `UICollectionView`, Auto Layout, and Combine-based observation where appropriate.
- Use the official Telegram iOS source code as the primary behavioral and layout reference. Inspect a sibling `../Telegram-iOS` checkout when available, and port the relevant logic instead of replacing it with a simplified approximation.
- Adapt referenced Telegram behavior to BetterTG's UIKit and TDLibKit architecture; do not copy unrelated Telegram infrastructure into the project.
