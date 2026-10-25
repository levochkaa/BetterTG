# Foreground root-list restoration proof — 2026-10-02

- A30a worker `b8d8432`/`469bad4` integrated as `0b36884`/`992b564`. Accepted-source readiness clears on activation/background;
  obsolete clients cannot announce readiness. Navigation replaces only opted-in Main entries for the same account, with exact
  stack/source/generation checks and transition/modal deferral. RootVM must already match the account; its scheduled update retries
  restoration. Account switches and unrelated route objects retain their existing handling. Notification-service ownership is unchanged.
- Main carries selected folder, search query/focus and per-folder chat-ID/pixel anchors. Restore waits for current diffable completion
  and usable layout; newer query/drag invalidates it. Fresh folder object identities rebuild children without resetting their viewports.
  Chat, ForumTopics, Archive and already-open folder editors are deliberately not rebound; A30 remains open there.
- References: pinned current/pre-Liquid `ChatListUI/Sources/ChatListController.swift` 4039–4093/3969–4019 selected-filter preservation
  and 4676–4700/4620–4646 content-ready search; BetterTG adapts these contracts to UIKit/TDLib client epochs.
- All ten initial Swift files formatted together; primary build `build-Debug-20261002-164821-26680-8524.log` passed (19s).
  Model-ready follow-up formatted both files, build `build-Debug-20261002-165126-73786-13702.log` passed (9s), both without warnings.
  Earlier `build-Debug-20261002-164734-18341-15729.log` records a premature build of an unresolved App-hook cherry-pick conflict;
  both hook registrations were retained before these clean builds. Worker logs have `worker-A30a-`/`worker-A30a-model-` prefixes.
- Authenticated audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `74615`, `992b564`:
  `-ui-probe-client-restoration` passes readiness, A1→A2→A3/stale/account/stack/transition/model fences, retained chat identity,
  production UIKit viewport capture/restore, prepend/missing/clamp and delayed-layout/query/drag checks. Result in
  `.build/ui-probe-evidence/astra-a30a-primary`; six prior permission/action/store/edit regressions pass in `astra-a30a-regressions`.
- Production smoke: scroll groups → HOME → app icon; same PID, selected group folder and visible peer-row Y positions preserved.
  Long-press group tab → Edit Folder opens the real authority-gated editor; Back without Save. A second cycle preserves the own empty-result
  search query and focus: typing `7` without another tap appends to the restored query. Software keyboard stays hidden; no keyboard-layout
  claim. Own search was cleared with Close. Visually inspected captures under `astra-a30a-ui`: `groups-scrolled.png`,
  `groups-restored.png`, `folder-editor-restored.png`, `search-before-background.png`, `search-restored.png`;
  `search-restored-typing.png` plus AX readback records retained first-responder input. No real message/folder/account mutation.
