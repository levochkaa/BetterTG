# A30f1 retained profile editor and fresh save authority — 2026-10-02

- `df41469` (worker `ae69e9e`) keeps the exact editor, raw fields, selection and local errors through same-account client
  replacement. A fresh immutable account/actor/client scope is reserved for each explicit Save; stale Ready cannot renew it.
  Account/actor departure permanently revokes the editor, including A→B→A. The actual parent retains only its attached,
  immediate, non-revoked editor; other profile children and full profile restoration remain separate.
- A27 permission reads remain fresh before each title/description write. Predispatch loss sends nothing; after first dispatch,
  client/readiness loss leaves an explicit uncertain result without replay. Accepted partial ACK advances only that field's
  baseline. Late ACK/error cannot update fields or navigation; newer typing prevents an old success from closing the editor.
  No server-conflict reconciliation or process-death profile draft storage is added.
- References: current/pre `PeerInfoHeaderEditingContentNode.swift`111–160/97–142 reuse existing editing fields;
  `PeerInfoScreen.swift`1663–1755,1920–1956 / 4296–4377,4507–4543 captures explicit edit/save state. Pinned TDLib `td_api.tl`
  13225–13230,13329–13334,13415–13423,14617–14627 supplies the existing name/bio/chat-info and authorization contracts.
  No Telegram infrastructure copied. Primary reviewed the session, parent gate, editor and injected endpoint proof.
- Five Swift files formatted together; `build-Debug-20261002-232350-7050-2496.log`: PASS14s, zero warnings. Native editor
  probe at `df41469`, PID `9957`, passes production session/retention helper, actual UIKit fields/selection, stale Ready,
  immutable payload/client, partial writes, typing revision and detached/account/actor rejection. A27 permission, generic
  navigation and folder-flow regressions pass. Fresh results `23:24:47–23:24:52`; no server mutation.
- Real Saved → own Profile → Edit: enter agent-only `AstraDraft`, Home → app icon. Same PID `9957`; lifecycle log records
  ownership release `23:32:55`, recreation/Ready `23:33:18`. Same field/caret survives; typing `2` yields `AstraDraft2`.
  Back retires the stale parent to restored Saved. Reopen Profile/Edit: original empty Last name is intact. Save was never
  pressed; agent-only draft discarded. Private proof `.build/ui-probe-evidence/astra-a30f1-primary`.
- Settled foreground screenshots also expose A37 first-field overlap. This is bounded state/authority proof, not clean layout
  parity. Hardware keyboard/IME, live account switch, authorized server saves and full profile/gallery recovery remain unverified.
- A37 diagnostic follow-up adds opt-in `-ui-diagnose-profile-editor-layout`: at most 32 public bar/safe-area/field-frame samples
  on editor state/layout events, no text/IDs and no forced layout or production behavior change. Two-file format and
  `build-Debug-20261002-234312-52588-868.log`: PASS14s, zero warnings. Runtime geometry classification pending.
- At `be30413`, PID `56662`, both unfocused and focused same-PID foreground runs have clean settled screenshots. Instant
  ready-state samples report bar maxY150/safe minY116, but these are transition samples, not proof of persistent geometry.
  The original `df41469` overlap remains a valid observation; its trigger/root cause is unconfirmed. Add a delayed 0.5s
  `settled-state` sample without forcing layout; one-file format and `build-Debug-20261002-235130-62705-6888.log`: PASS8s,
  zero warnings. Agent-only `AstraLayout` was discarded via Back without Save. Private proof `.build/ui-probe-evidence/astra-a37-primary`.
