# Range-waiter repair proof — 2026-10-02

- Scope: A01/A02 only. Preserve range planning, source/client ownership, finite fetch limits and cancellation generations. A fresh
  UUID identifies each waiter registration; sleep cancellation exits, and a delayed old callback cannot expire a replacement.
  Update-sequence checks cover size discovery, full-file fallback and range-prefix waits without losing an already-delivered update.
- One SwiftFormat invocation covered `TDLibVODRangeSource.swift`; `./build.sh build` passed without warnings in
  `.build/logs/xcodebuild/build-Debug-20261002-141955-60817-17803.log`. Independent diff review found no blocker.
- `./build.sh run --skip-build -- -media-probe-vod-ranges`, iPhone 17 Pro / iOS 26.5,
  `8108A92F-7E93-49C8-87F4-FA53A5A40A99`, PID `74821`: idb pulled
  `.build/ui-probe-evidence/astra-vod-range-probe.txt/vod-range-probe.txt`. It reports
  `deadline-token/rearm=true`, `update-before-wait=true`, existing cache/lookahead/coalescing/disjoint-seek/offline/exact-size and
  last-lease-revival checks passed. This is a deterministic production-source probe with injected file transport, not live Telegram VOD.
- Separate runtime blocker B01: after the probe, this existing Simulator process terminated with `EXC_BAD_ACCESS` in pinned TDLib
  `td::get_page_blocks_rich_message_media` → `RichMessage::parse` → `MessagesManager::parse_dialog` while loading its database.
  Report: `/Users/lev/Library/Logs/DiagnosticReports/BetterTG-2026-10-02-142322.ips`. The screenshot shows Home, so it is not a passing
  app-flow smoke. No database reset/removal was performed. Verify probes on an isolated Simulator and separately investigate this
  dependency/data compatibility failure; the original database remains unverified.
