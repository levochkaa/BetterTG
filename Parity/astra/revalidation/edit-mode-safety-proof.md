# Edit-mode safety proof — 2026-10-02

- A24 worker `8aa914f` integrated as `163753e`. Primary reviewed the entire policy/probe and all edit-session assignment sites.
  `ChatVM` dispatches explicitly between ordinary/invalid-edit/edit, captures the message/formatted payload, and checks session,
  text revision, task cancellation and current location after request completion. Closing Edit preserves the ordinary reply;
  newer typing or a reopened same-ID session survives an old success/error. Semantic entity conversion A25 remains unchanged.
- Six Swift files formatted in one invocation; warning-free primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-161023-77945-13703.log` (10s). Worker log copied with `worker-A24-` prefix;
  `.build/ui-probe-evidence/astra-a24-worker/README.md` preserves scope and reference notes.
- Same authenticated audit Simulator, PID `79320`: `-ui-probe-composer-edit -media-probe-voice-finalization
  -media-probe-draft-outcomes` all pass. Results are under `.build/ui-probe-evidence/astra-a24-primary`, `astra-a24-voice`,
  `astra-a24-drafts`. Edit probe executes the production submission/token policy with suspended callbacks: zero ordinary sends
  for invalid edit, immutable payload, A→B→A revision, same-ID reopen, caller completion-delivery fence, cancellation, unchanged
  success and empty media caption. It uses counters and fixtures, not a real ChatVM, keyboard, selected-attachment view or TDLib
  server edit. Production wiring/disabled action is source/build-proved only. No account data or messages were changed.
