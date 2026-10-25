# A40 complete build-warning visibility — 2026-10-03

- Fix commit: `f08f4e7`.
- Full integration log `014324-25949-6943` line264 reports `Metadata extraction skipped. No AppIntents.framework dependency found`
  for BetterTGNotificationService. `script/build.sh` and its compact formatter hid this category; the formatter also aggregated
  SwiftFormat warning details. Remove these filters so each warning remains visible, and require complete-log checks in both
  synchronized instruction files.
- The notification extension declares no AppIntent/AppShortcut; it uses legacy `Intents`/`UNNotificationServiceExtension`.
  Remove its unused AppIntents import and set target-only `LM_SKIP_METADATA_EXTRACTION: YES`. Local Xcode26.6 task-producer
  inspection confirms the native Boolean omits the inapplicable stage, rather than quieting emitted diagnostics. Main-app
  extraction configuration is unchanged. Restore extraction if extension AppIntent declarations are introduced.
- Independent six-file review, shell syntax and parser fixtures pass; skipped/disabled metadata, SwiftFormat per-rule and
  uppercase warning examples remain visible. One-file SwiftFormat0/1; `build-Debug-20261003-015029-27777-31071.log`: PASS5s,
  full log zero warnings/errors, extension recompiles with no extraction task. The next build `015206-28264-17404` exposes an
  existing race between `Remove Static TDLib Artifact` and automatic framework copy/sign; A41 repairs it below.
- Historical full logs explicitly rechecked: A38 `002923`, `003813`, `004329`; A39 `005409`, `005819`; worker `013700` all have
  zero warnings/errors and successful builds. A39 `010725`, `011303`, `011704` also pass full-log checks. Their claims stand.
  Other compact-only historical claims remain unverified;
  no broad retroactive assertion is made. Telegram/TDLib behavior unchanged; no runtime notification delivery proof claimed.
