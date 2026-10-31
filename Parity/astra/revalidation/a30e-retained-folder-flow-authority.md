# A30e retained folder-flow authority — 2026-10-02

- `3dc1610` (worker `4a5dc84`) keeps the existing folder list/editor/selector/order controllers and their local name, rules,
  selected IDs, raw search query and ordering. `FolderFlowSession` renews only future immutable action scopes after matching
  account, current client, Ready source and Root model. Account departure permanently revokes the flow, including A→B→A.
- Predispatch rollover sends nothing. Readiness/client loss after create/edit/delete/reorder dispatch leaves an explicit
  uncertain result with retained inputs and no automatic replay. Late ACK/error cannot pop, present or enable another save.
  Main → Add Chats is owned by the retained selector, not a retiring Main. Full-definition updates retain existing semantics;
  remote conflict merging, process-death drafts and uncertain-result server reconciliation are not added.
- Initial actual-UIKit probe at `3dc1610`, PID `65721`, failed detached-owner delivery: UIKit retained a popped view in its
  window. `4077e41` (worker `af67ce0`) replaces that insufficient window check with actual containment/navigation/presentation
  membership up to the exact window root. The original assertion stays unchanged; covered entries, nested/page children,
  modal navigation, animated pop, residual pixels and detached navigation subtrees have explicit regressions.
- References: pinned current/pre `ChatListUI/Sources/ChatListFilterPresetController.swift` 550–576,1399–1429 / 546–572,1394–1424
  preserve local editor state with account context. Pinned TDLib `td_api.tl` 13154–13172 defines the existing get/create/edit/
  delete/reorder APIs. No Telegram infrastructure or new account storage is copied.
- All six Swift files formatted together. Primary integration builds `build-Debug-20261002-230359-64579-5399.log`: PASS26s and
  `build-Debug-20261002-231025-79060-7092.log`: PASS55s, zero warnings. The first sandbox-only attempt could not reach
  CoreSimulator; the wrapper succeeded with normal host access, without resetting any Simulator.
- Audit Simulator, iOS26.5, source `4077e41`, PID `80658`: actual folder-session/list/editor/selector/order probe passes;
  immutable scopes, repeated/stale Ready, predispatch denial, all four uncertain mutations, partial UI attachment and account
  revocation are covered with injected endpoints and zero server writes. List-action, navigation-restoration, Root authority
  and accepted-update projection regressions also pass. Fresh output mtimes `23:12:16–23:12:22`.
- Real UI source `3dc1610`, PID `65721`: local New Folder name `Astraflow`, Groups rule and caret survive Home→app-icon
  foreground; Always Include remains usable. Lifecycle log records ownership release `23:08:33` and restoration `23:09:07`.
  Source `4077e41`, PID `80658`: active selector query `Saved` and Saved Messages checkmark survive another Home→foreground.
  Close Search → Done returns to the same unsaved editor with `Always Include, 1 chats`; the local callback remains usable.
  No folder was saved and no conversation opened. Private proof, including initial failure:
  `.build/ui-probe-evidence/astra-a30e-primary`. Server mutations, live account switch, IME and interactive reorder remain unverified.
- Cold and post-foreground selector screenshots also show pre-existing blank title rows, a white Done checkmark and native
  bottom search. `CustomChat.displayTitle`, subtitle and sorting are unchanged by this slice: empty raw titles sort first;
  all `.user` rows are labeled Contact. Deleted/unknown row classification needs content-free counters before attributing it.
  System Done/prominent foreground with hidden background is an A32 contrast gap; do not claim visual parity from probe flags.
  Documentation checkpoint build `build-Debug-20261002-232053-99468-14280.log`: PASS11s, zero warnings; prohibited production/
  dependency marker scan empty, AGENTS/CLAUDE synchronized.
