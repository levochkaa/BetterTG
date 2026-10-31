# A30g member/admin route recovery — 2026-10-03

- Baseline `3d0873c` (documentation HEAD `b5c982a`): profile topmost gate233–239 and removal954–982 discard the
  profile suffix while its Members/Admins child is visible. The child retains an immutable old client and does not participate
  in navigation restoration. This is distinct from the already-supported ordinary profile editor.
- Actual audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone17Pro/iOS26.5, PID `30616`: existing basic group →
  Profile → Members shows three rows at y116/189.333/262.667, each73.333pt. Home02:19:29 releases TDLib ownership02:19:30.327;
  foreground02:23:52.455 restores it. Settled hierarchy and screenshot show Chat, with Members and Profile removed; PID stays30616.
  Private pixels are under `.build/ui-probe-evidence/astra-a30g-baseline`. No tag/editor/save/send/delete/export action occurred;
  normal chat-read side effects remain possible. idb supplies input/hierarchy; `simctl io screenshot` supplies pixels because the
  idb screenshot backend is unavailable. The Simulator window was not activated or shut down.
- Bounded repair contract: retain only a quiescent exact adjacent Profile/Members stack through same-account Ready; transfer
  accepted member IDs, raw cursor and row geometry/anchor, never old TDLib member objects or action authority. Re-read current
  availability and membership with bounded page demand; fence account/actor/client/attempt and late callbacks. Preserve raw
  server order/pagination and fresh tag preflight. Active tag editor, Save uncertainty, modal and active gestures stay separate.
- References: pinned current/pre `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoMembers.swift`
  136–190/136–188 and305–307/292–294 retains account-owned accepted state/loading/pages. TDLibKit `1.5.2-tdlib-1.8.66-022d6020`,
  TDLib `022d6020`: `getBasicGroupFullInfo`, `getChatAdministrators`, `getSupergroupMembers`. No Telegram infrastructure copied.
  The implementation and bounded after-fix proof follow; these references do not establish complete member-management parity.
- Baseline documentation validation `build-Debug-20261003-022901-39675-31468.log`: PASS5s; complete log has zero warnings/errors.
  No Swift change in this checkpoint.
- `293c6d0` (worker `ea60670`) implements exact adjacent Profile/Members retention, same-account/actor restoration,
  stable member-ID/pixel geometry and neutral quarantined rows. Current `getBasicGroupFullInfo`, `getChatAdministrators`,
  or one 100-row `getSupergroupMembers` page per demand revalidates rows. Raw offset remains separate from deduplicated IDs
  and the retained extent. Source/generation/attached-owner checks precede dispatch and follow every response; scoped
  member/group/permissions changes invalidate immediately, with semantic full-info dedup preventing self-triggered replay.
- Independent review found that a replaced Profile can stay unloaded beneath Members across another ownership epoch.
  `5e5adef` (worker `b4d3b67`) installs ownership/Ready observation at init, keeps UI/media work view-bound and transfers
  accepted seed state without materializing the covered Profile. `41aeb0c` (worker `ce408f6`) adds plain visible Retry for
  deep retained-page failures, synchronous neutral error cells, and per-failure UUID/generation/source/top-owner checks.
  Errors do not automatically retry; old buttons cannot consume a newer failure. Both followups passed independent review.
- Primary integration builds `build-Debug-20261003-025548-60862-15401.log` (10s) and
  `build-Debug-20261003-030933-90779-22519.log` (15s): PASS, full logs contain zero warnings/errors; changed Swift files
  formatted together. Initial PID `62735` Members probe failed an immediate combined UIKit pop/retirement assertion.
  The corrected fixture retains synchronous authority rejection, then boundedly waits for actual lifecycle cancellation;
  it does not relax production guards. Source `41aeb0c`, PID `99916`: Members and existing Profile probes both pass.
  Members proof covers production replay/revision/ABA and coordinator helpers, actual unloaded-Profile callbacks, native
  Members table/quarantine/anchor/fresh partial page/pop cancellation, visible Retry, no auto-retry, covered/unready/stale
  generation/old-button rejection and predispatch cancellation. Generic parent navigation entries remain value adapters;
  no TDLib RPC, server permission change or global client swap is injected by the probe.
- Actual source `5e5adef`, PID `62735`, same audit Simulator: Members retains all three baseline row frames through
  release03:01:08.920 → restore03:02:00.705 and release03:07:27.277 → restore03:08:13.888. The second cycle leaves the newly
  replaced Profile unloaded beneath Members. Profile replacement acceptance logs occur03:02:00.929 and03:08:15.915.
  Back reaches Profile; Admins shows one Owner row at y116/height73.333, then retains it through release03:10:49.847 →
  restore03:11:36.553, acceptance03:11:36.718. Back again reaches current Profile controls. Settled rows contain no Updating
  placeholders. Names/IDs are omitted here; ignored pixels are under `.build/ui-probe-evidence/astra-a30g-primary`.
- Runtime bounds: small basic group only; no member/tag/editor/save/send/delete action, real network-error injection,
  live permission loss, large supergroup pagination or active-editor recovery. Normal chat-read effects remain possible.
  Native error fixtures prove the local path, not live offline recovery. Existing A32 native circular Back remains open.
- Documentation validation `build-Debug-20261003-031613-8760-19481.log`: PASS5s, full log zero warnings/errors. Forbidden
  production/dependency marker scan is empty; AGENTS/CLAUDE agree. No new Swift change in this documentation checkpoint.
