# BetterTG Agent Instructions

> Sync note: keep `AGENTS.md` and `CLAUDE.md` in sync. Any workflow or tooling change made in one file must be copied to the other in the same change.

## Build And Test

- Do not use XcodeBuildMCP or other MCP tooling for BetterTG build, test, run, or simulator validation unless the user explicitly asks for it.
- Build through the root multiplexer: `./build.sh build` (or `./build.sh`, which defaults to build).
- Run through the root multiplexer: `./build.sh run`. BetterTG currently has no dedicated test target, so build is the repository-level validation.
- Always run SwiftFormat after modifying Swift files. Pass every existing `.swift` file modified in the current task to a single invocation, and do not format the entire repository unless the user explicitly asks for it:

  ```sh
  swiftformat --config .swiftformat --cache ignore "path/to/File.swift" "path/to/File2.swift" "path/to/File3.swift"
  ```

- Before finishing any task, run `./build.sh build` after formatting to verify that the project compiles successfully. If the user explicitly asks not to build, follow that narrower scope and report that build verification was skipped.
- Treat every warning emitted by `./build.sh build` as a handoff blocker. Fix the warning and rerun the build before treating the task as complete; a successful build that still contains warnings is not a clean build. Do not silence or suppress warnings merely to make the output quiet. If a warning comes from external code and cannot be fixed safely within the task scope, report it as a blocker and ask the user how to proceed instead of claiming completion.
- The build script owns Xcode environment setup, project generation, TDLib model generation, package resolution, derived data location, and simulator selection.
- Pass all build and run overrides as wrapper options; never prefix `build.sh` with configuration environment assignments. Available overrides include `--xcode`, `--configuration`, `--simulator`, `--simulator-id`, `--ios`, `--device-id`, `--derived-data`, `--cloned-source-packages-dir-path`, `--xcodebuild-log-dir`, `--launch-argument`, `--console`, `--no-code-signing`, `--skip-build`, and `--simulator-boot-timeout-seconds`.
- Use `./build.sh build --device` to build for the available paired physical iPhone and `./build.sh run --device` to build, install, and launch on it. Device builds use Xcode automatic provisioning. Pass `--device-id ID` only when a specific physical iPhone must be selected.
- Put app arguments after the `--` delimiter when an automated launch smoke needs them; repeated `--launch-argument VALUE` options remain available for compatibility. Do not bypass `build.sh` with a direct simulator launch.
- Use `./build.sh run --device --console -- ARGUMENT...` when physical-device stdout/stderr must remain attached for live diagnostics. The command intentionally waits until the app exits.
- Swift packages are cached separately from DerivedData by a graph hash containing the `project.yml` package declarations, including the pinned TDLibKit 2 revision, and exact Xcode version. Reuse the graph cache and restored `Package.resolved`; do not delete or redownload it when clearing DerivedData.
- Default DerivedData and module caches are isolated by Xcode version. Build and run actions serialize the generate/package/codegen/xcodebuild portion through `/tmp/bettertg-build.lock`; install, launch, and attached console run after the lock is released.
- Xcode builds print compact progress and save complete command output under `.build/logs/xcodebuild`; use `--full-output` only when the complete stream is needed in the terminal.
- Compact output must retain every build warning. Check the complete log before claiming a warning-free build. The notification extension declares no AppIntents and skips that inapplicable metadata stage; restore extraction if AppIntent declarations are added.
- Use `./build.sh clean-intermediates` to remove compilation/index/module/SDK-stat intermediates while preserving app products, complete logs, and the separate Swift package cache. `./build.sh run --skip-build` reuses the compatible product for the selected Xcode, configuration, and platform without running XcodeGen, package preparation, TD generation, or xcodebuild.
- Simulator runs wait for bounded `simctl bootstatus` readiness before install. Do not close or shut down the booted Simulator when finishing a task unless the user explicitly asks.
- Simulator runs open the Simulator app in the background, preserving the user's current application focus. Do not activate it separately during automated smoke.

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
