# A35 scope notification read authority — 2026-10-02

- `67fdae6` (worker `d7f2462`) reserves three typed scope revisions synchronously before dispatch. A new load replaces old
  reservations; an accepted scoped update revokes only its scope. Each current response publishes immediately, with immutable
  client/Root ticket validation before and after await. Failure leaves accepted values unchanged; stale cleanup cannot revoke
  a newer request. Root account/client invalidation clears ownership. No notification settings are written to TDLib.
- References: current/pre `TelegramCore/Sources/State/ManagedGlobalNotificationSettings.swift`80–98 preserves current preference
  state at asynchronous commit; pinned TD `td_api.tl`10554–10555,13460–13461 supplies update/get scope semantics. No upstream
  infrastructure copied. `FolderView` consumes the existing published dictionary for mute presentation.
- Five-file integration format/build `build-Debug-20261002-223928-27434-8714.log`: PASS50s, zero warnings. Source `67fdae6`,
  PID `31611`: actual loader with held continuations passes update-before-dispatch, in-flight update, immediate publish,
  newer overlapping batches, late success/failure, new load after update, account/client/epoch and cancellation. Root/insertion
  regressions pass; all three files freshly written `22:41:07`. Evidence `.build/ui-probe-evidence/astra-a35-primary`.
  Combined A34 PID `44216` repeats the loader proof. No server mutations; visible mute-badge race remains source-only.
