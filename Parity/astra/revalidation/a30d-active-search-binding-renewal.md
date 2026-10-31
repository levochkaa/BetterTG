# A30d active-search binding renewal — 2026-10-03

- `8faa541` (worker `1b113c0`) retains the exact ForumTopics controller/search controller/field/table/data source and swaps
  only its immutable-client VM after current account/actor/Ready and fresh route metadata. It captures raw query at commit,
  preserving field text, UTF16 selection and focus. IME, foreign modal, native transition and table interaction defer via events.
  Global navigation modal guards remain unchanged. Every queued VM sink/target/error/metadata result has model+binding authority.
- A42 snapshot batches now retain their supplying clients as well as models. Old native completion always closes its own
  transaction lifetime; stale viewport/load effects are denied. Renewal waits for all pending/native batches to drain. Metadata
  failure clears stale rows and shows explicit Retry with exact failure/source/binding checks; typing does not auto-retry.
- Independent review repaired three introduced seams before acceptance: `1bb3ace` (`22c56a1`) keeps account/actor notifications
  synchronous so departure/return cannot disappear in queued sampling; `0eeadea` (`4c5313e`) permits original-source rendering
  before getMe supplies an actor, latches first known actor only under exact original-source Ready and rejects unknown-identity
  epoch departure; `22ef89e` (`f516869`) exposes a failure latched before view loading when Back first reveals that controller.
  Cross-epoch renewal still requires known identity. Metadata and target waits keep controller ownership weak.
- References: pinned current/pre `ChatListController.swift`4665–4672/4609–4616 and
  `ChatListSearchContainerNode.swift`115,143–144,712–720 /97,120–121,660–668 preserve account-bound query ownership.
  Pinned TDLib022d6020 `getChat/getForumTopics`, query+cursor and account-client update transport remain unchanged.
  BetterTG client-epoch restoration is its own adaptation; no upstream infrastructure is copied.
- Six Swift files formatted together. Primary builds `035458-85956-3726` PASS8s and `035939-97796-21734` PASS7s;
  DEBUG fixture builds `040658-11205-23255` PASS12s and `041539-25602-17621` PASS8s. Full logs have zero warnings/errors.
- Actual source `22ef89e`, PID1590, audit Simulator/iOS26.5: Cyrillic `фке` has zero results with focused software keyboard.
  Home releases ownership04:03:50.098; foreground restores04:04:41.091 and accepts search binding04:04:41.269 in the same PID.
  Clearing without Cancel returns all six topics. New Cyrillic `г` filters to one row after settlement. Keyboard Search hides
  keyboard but leaves search active. Second release04:06:54.014→restore04:07:55.359→binding acceptance04:07:55.524 preserves
  query/result and does not open keyboard. Clearing again without Cancel returns six rows. No topic opened or edited.
  Private screenshots/README: `.build/ui-probe-evidence/astra-a30d-active-search`; idb input/AX with simctl screenshot fallback.
- First native probe at `22ef89e`, PID99423 failed `foreign modal`: its presenter assumption was wrong. DEBUG-only `2f84ef4`
  (`f55cfc9`) verifies actual reciprocal modal ownership and attachment. Rerun PID19367 confirms UIKit forwards presentation
  to UINavigationController while search stays active; modal guard/retry pass, but immediate search-dismissal+pop times out.
  `65dcc5c` (`8f66706`) waits for native didDismiss, verifies real pop result/stack exclusion and bounded parent=nil/retirement.
  Its actual-controller probe passes PID25951 at04:16:19, including Unicode selection, stale sinks, native batch drainage,
  metadata supersession, Ready gap, IME, explicit/stale Retry, nil→known actor, unloaded failure and account/actor ABA.
  `8b55479` (`2a17c74`) further waits for the exact held metadata task before checking post-pop rejection; final rerun passes
  PID27782 at04:18:38, fresh container `D5F001F3-D5D3-4E2D-8D86-1211F90B0398`.
  Its build `build-Debug-20261003-041749-27326-24775.log`: PASS8s, complete log zero warnings/errors.
- Separate `2f84ef4` native forum snapshot/restoration regressions pass PID24685 at04:13:52/04:13:50. These cover production
  snapshot/cell helpers and coordinator/viewport/seed contracts, not live RPCs. Fixtures use isolated VMs and controlled
  metadata without global account mutation, TDLib leases or server RPC. Real pagination/metadata failures/route-kind change,
  interactive pop and simultaneous search-dismissal+pop remain unverified. A32 native Back/Search visual gaps remain open.
  Documentation build `build-Debug-20261003-042015-29687-457.log`: PASS4s, full log zero warnings/errors. Production/dependency
  forbidden-marker scan is empty; AGENTS/CLAUDE remain identical.
