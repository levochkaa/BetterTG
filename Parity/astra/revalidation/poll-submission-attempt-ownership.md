# Poll submission attempt ownership — 2026-10-02

- A31 `ea88983` gives each accepted vote attempt an immutable token. The queued RPC checks that token and current route before
  sending; failure and deadline callbacks may clear only their own attempt. A stale callback neither cancels the replacement
  deadline nor publishes a misleading idle state. Authoritative selection changes invalidate old attempts; retry keeps local choices.
- Reference: pinned pre-Liquid `submodules/TelegramUI/Sources/ChatController.swift:3422–3430` owns per-message poll requests;
  `ChatMessagePollBubbleContentNode` reflects current in-progress selections. TDLib `022d6020` `SetPollAnswer` uses message/chat
  identity and zero-based option IDs. No Telegram infrastructure copied or network cancellation guarantee assumed.
- Three Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-174113-33012-16805.log` (10s). The preceding sandboxed attempt could not connect to
  CoreSimulator; the same wrapper succeeded with host access, without changing or resetting a Simulator.
- Audit Simulator PID `36667`, `-ui-probe-poll-submission`: actual store, registered deadline and already-running deadline callback
  tests pass for timeout/retry/late failure, A→B→A authoritative reset, exact replacement timer ownership, no stale notifications,
  pending-choice preservation and duplicate completion. A28/A30b1/terminal-navigation regression probes also pass in
  `.build/ui-probe-evidence/astra-a31-primary`. ChatVM wiring is source-reviewed; no real vote or delayed server RPC was performed.
