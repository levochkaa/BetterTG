# A42 forum-search snapshot cell ownership — 2026-10-03

- Actual source `f7d7090`/docs`3b7ab09`, audit Simulator PID `42180`: existing real forum → active search → three-character
  Cyrillic query. At02:31:53.810, UIKit throws `NSInternalInconsistencyException`: reconfigure expected the existing `ForumTopicCell`
  but received a new plain `UITableViewCell`. Crash report `BetterTG-2026-10-03-023158.ips`, incident
  `E8889D35-E206-4228-9339-F3C0A2617229`; stack reaches `applySnapshot`341 from queued topics sink307. No Home was sent.
- Cause: the provider resolves a captured snapshot ID against newer `viewModel.topics`; a miss returns another cell instance.
  `ForumTopicsSnapshotState` now owns the outgoing/incoming models for one apply, coalesces the next payload, prunes removed models
  only on matching completion, and rejects retired callbacks. The provider always returns its registered dequeued cell; unexpected
  missing models clear pixels, icon work and accessibility/actions. Stable displayed ID plus current accepted/raw-query membership
  gates selection. Pagination uses settled displayed rows; viewport restoration waits for the last pending apply.
- Contracts retained: native UITableView/diffable animation, topic IDs/order, TDLib pagination, search semantics, immutable client,
  target navigation and account fences. No search-owner/foreground rewrite or infrastructure import. References: pinned current/pre
  `ChatListUI/Sources/ChatListSearchContainerNode.swift`712–720/660–668 keeps the ongoing query stream; UIKit's runtime assertion
  supplies the exact same-cell reconfigure contract. TDLib `022d6020` `getForumTopics` and typed topic updates are unchanged.
- Independent source review found no further blocker. Four changed Swift files formatted together. Initial `023925-49399-14038`
  build exposed probe actor/immutable-model errors and one explicit-self error; repaired without suppression. Complete logs
  `build-Debug-20261003-024008-49732-21018.log` and `024232-51718-5650` both PASS7s with zero warnings/errors.
- Initial native probe PID `50825` timed out with an unattached animated table. The DEBUG fixture now attaches its real table to
  a temporary UIKit window and tears it down; no production timing gate was weakened. PID `54675` passes production-state
  serialization/coalescing/outgoing lifetime, real diffable reconfigure of the same production cell, missing-model cleanup and
  retired completion rejection. Existing forum-restoration regression also passes. This native consumer does not inject the full
  controller/VM transport or verify navigation actions.
- Actual fixed production code PID `50825`: matching query shows one row; clear/new unmatched query settles to No topics found;
  further quick query changes keep the same PID. PID `54675` repeats the exact original Cyrillic query and settles to No topics
  found without crash; three-minute exception-log read is empty. No topic selected or message/topic mutation occurred. Private
  before/after pixels and failed-fixture notes: `.build/ui-probe-evidence/astra-a30d-search-baseline`. Background-search restoration,
  result selection and multi-page search remain separate proof limits. The native bottom search island is still an A32 UI gap.
- Final `build-Debug-20261003-025014-56598-7723.log`: PASS4s, complete log zero warnings/errors; prohibited production/dependency
  markers absent. No whole-repository formatting or account/data reset.
