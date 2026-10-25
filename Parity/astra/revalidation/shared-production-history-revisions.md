# Shared production history revisions — 2026-10-02

- A30b2 phase 1 `fe01cde` (worker `4c9142a`) wires the history ledger into ordinary ChatVM and the optional seeded constructor.
  Complete accepted messages install their body before metadata awaits; one four-message lane hydrates metadata. Partial updates,
  permanent deletion and source retirement invalidate older reads. Reaction/pin owners retain their wrapper until both settle.
  Normal pagination checks the same token at synchronous merge. Prepared windows carry only fetched values and an unconsumed token;
  actual installation rechecks revisions and merges current messages, preserving intervening updates instead of overwriting them.
- Restored latest history advances on raw pages, then filters exact topic for rendering. Ready/manual retry is event-driven,
  including one deferred event during batch/latest RPC; a plain failure never loops. Confirmed missing history removes display state
  only; durable recording/send outcomes and file cleanup still require their accepted TD updates. No storage schema changes.
- References: pinned ChatInterfaceState/history restoration and exact TDLib `getMessage` 404 path recorded above; captured-client
  `getMessage/getChatHistory/getMessageThreadHistory` and generated update models. Source review caught prepared-window admission
  before its actual install and sender updates missing a bare message; both were corrected before integration.
- Four Swift files formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-183613-37316-13873.log` passes
  without warnings (33s). `fe01cde`, PID `41056`, `-ui-probe-chat-restoration-state` passes actual ledger/cursor cases: live body,
  partial-before-body/during-hydration, deletion, shared page token, overlapping mutation owners, deferred Ready/error/cancel and
  foreign-topic raw bridge. A23 Chat/Root, A31 poll and animation-authority regressions pass in
  `.build/ui-probe-evidence/astra-a30b2-production-primary`. Worker notes/logs are preserved separately.
- Probe read/hydration closures are isolated: actual ChatVM constructor, ordinary timeline and delayed TDLib transport still need
  production smoke. ChatView restoration is not enabled; the controller must transfer a quiescent composer/history, settle its
  one-shot pixel anchor, then start freshness. Raw unresolved reply/forward dependencies, A22 scroll interaction epochs and other
  secondary-route restoration remain open. This phase is production wiring, not a complete A30 claim.
