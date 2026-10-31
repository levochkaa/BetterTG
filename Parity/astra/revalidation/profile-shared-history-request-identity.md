# Profile shared-history request identity — 2026-10-02

- A28 `b717304` adds per-request authority independently of the selected filter. Tab change invalidates it before cancellation;
  every success/error/cancellation path consumes only its own ID before touching the task or UI. Existing account/client/tab checks,
  pagination cursor, deduplication, gallery retry and query semantics remain intact. No network cancellation guarantee is assumed.
- Reference: pinned `PeerInfoVisualMediaPaneNode.swift`, current 1726/1792 and pre-Liquid 1660/1725, scopes and replaces history
  subscriptions; TDLib `022d6020` `SearchChatMessages` topic/filter/from-message contracts checked directly. No Telegram infrastructure copied.
- Three Swift files formatted together; primary warning-free wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-172655-9917-30165.log` (10s). Audit Simulator PID `10397`:
  `-ui-probe-profile-history-request` passes production token helper checks for A→B→A late success/error/cancel, busy replacement,
  current exactly-once completion, invalidation and retry. Results plus A27/A16/A17/A30b1/A30a regressions are under
  `.build/ui-probe-evidence/astra-a28-primary`. The controller's success/catch/reset wiring is source-reviewed; the probe does not
  construct a real profile, delay a TDLib RPC or exercise tab gestures. No real account/profile/message changes.
