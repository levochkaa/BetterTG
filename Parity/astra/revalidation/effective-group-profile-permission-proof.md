# Effective group profile permission proof — 2026-10-02

- A27 worker `1a78906` integrated as `cab49d9`; primary reviewed both production controllers, shared policy/authorization and
  complete probe. Basic-group admins keep all applicable rights; ordinary members use default `canChangeInfo`; restricted
  supergroup members require membership and both effective/default rights. Supergroup admins retain allowed member rights;
  broadcast channels still require creator/admin authority. Self-profile editing is unchanged; owned-bot editing is not added.
- Fresh `getChat` + `getChatMember` on appearance closes a real entry gap: ChatVM's live permission cache does not update
  `CustomChat.chat.permissions`. Capability state owns its own source/revision, consumes only scoped permission/group updates,
  and rejects an older refresh after a rights event. Unrelated title/photo metadata no longer owns capability state. Each title
  and description write independently rereads permission and verifies source/actor/returned IDs; a revoked second write is
  blocked while existing partial-success handling is preserved. Server authorization remains authoritative; these reads are not
  an atomic permission transaction.
- References: pinned current/pre-Liquid `PeerInfoData.swift` 2395–2427/2158–2191 and
  `TelegramCore/Sources/ApiUtils/TelegramChannel.swift` 209–226/207–224. TDLib `022d6020` `Chat.permissions`,
  `ChatMemberStatus`, `ChatPermissions`, `setChatTitle` and `setChatDescription` contracts were checked directly.
- All five Swift files formatted together; warning-free primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-164302-10912-6908.log` (10s). Worker proof README is copied to
  `.build/ui-probe-evidence/astra-a27-worker/README.md`, build log with `worker-A27-` prefix.
- Audit Simulator, PID `11755`: `-ui-probe-profile-info-permissions` passes 25 policy cases, fresh appearance capability,
  scoped live changes/stale refresh, per-write revocation, wrong account/client/actor/chat, cancellation and delayed completion.
  Result: `.build/ui-probe-evidence/astra-a27-primary/profile-info-permissions-probe.txt`. Production helpers run against
  suspended injected reads/writes; no real profile controller permission change or server save is claimed.
  A29/A12/A26/A14/A24 regressions all pass in `astra-a27-list`, `astra-a27-drafts`, `astra-a27-relocation`, `astra-a27-voice`,
  `astra-a27-edit`. No real profile/account/message mutation. Marker scan remains empty; A32 visual chrome remains open.
