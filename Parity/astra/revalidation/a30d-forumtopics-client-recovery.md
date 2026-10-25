# A30d ForumTopics client recovery — 2026-10-02

- `0580786` (worker `45c93ef`) adds prepared same-account replacement of only the stale topic-list navigation slot. Metadata
  is fetched with the captured ready client. Source/stack/account/chat/route-kind checks reject obsolete results; synchronous
  commit retires old page/topic tasks, subscriptions and open-chat lease. Adjacent restored Chat identity is preserved.
- Transfer accepted rows/query, raw search text, exact date/topic/message cursor, completed cursors, has-more, pending or failed
  reset/append, target-consumed state and stable topic-ID/pixel-offset viewport. In-flight cursors are not completed cursors.
  Raw input ahead of the stale VM restarts its own query at zero, without unrelated rows. A second epoch before view loading
  retains pending request intent. Cached rows are a display seed, not proof of fresh server-head reconciliation.
- Target lookup uses per-attempt identity through both captured-client awaits. Canceled/failed lookups can retry; an opened target
  is not replayed beneath an existing child. `80c748c` (worker `610c9ff`) keeps metadata/target continuations weak across awaits
  and adds a content-free actual-commit DEBUG log. Active UISearchController/IME/modal/drag defers replacement; dismissal and
  terminal interaction callbacks retry. Automatic active-search restoration remains unimplemented.
- Viewport applies only after the latest snapshot and usable layout; a new query or user drag cancels it. References: pinned
  current/pre `ChatListNodeLocation.swift` 9–12,240–297 / 9–12,158–205; immutable account-bound `ChatListNode.swift`
  1216,1934 / 1213,1939; `ChatListController.swift` 4665–4672 / 4609–4616. Pinned TDLib `GetForumTopics/ForumTopics`
  carries explicit query and cursor triple. Client recreation is BetterTG's adaptation, not upstream architecture copied.
- Five Swift files formatted together; `build-Debug-20261002-213659-45775-2887.log`: PASS9s, zero warnings. Audit Simulator
  source `80c748c`, PID `49689`: forum seed/target, actual generic coordinator and fixed-row UIKit viewport probe pass, together
  with client-restoration, Chat update delivery and Root authority regressions. Full suspended VM RPC/controller wiring is source-reviewed,
  not covered by that probe. Output explicitly retains these limits.
- A DEBUG-only `-ui-smoke-forum-list` opens one existing real topics route per process, without selecting a topic or presenting
  fixture UI. One-file build `build-Debug-20261002-213904-53667-8267.log`: PASS9s, zero warnings. PID `54903`, source `80c748c`
  plus that committed route helper: real populated list retains its rows through two Home→foreground cycles. The second bounded
  idb stream records `ForumTopics client restoration: replacement accepted` at21:44:41 in that same PID. No messages/topics were
  selected, no draft/send/settings mutation performed. idb's timeout cleanup emits an asyncio diagnostic, not an app/build warning.
- Private UI/probes: `.build/ui-probe-evidence/astra-a30d-primary`; worker refs/logs under `.build/a30d-proof`. The first log window
  ended before foreground; only the second proves acceptance. Search/IME, target navigation, dynamic-height/populated-anchor accuracy,
  live pagination and changed route-kind recovery remain unverified. The native bottom Search Topics island is additional A32 evidence.
- Active-search regression confirmed2026-10-03 after the separate A42 crash repair: production `f3b52d9`, PID `54675`,
  audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS26.5. Focused Cyrillic query `фке` has no results. Home releases
  ownership02:53:57.505; foreground restores02:54:43.789 in the same PID, preserving the field/keyboard. Clearing the query
  still leaves zero rows after settlement; Cancel02:56:55 triggers replacement acceptance02:56:55.227 and six topics return.
  Private `foreground-cleared-settled.png` and `cancel-recovered.png` under `.build/ui-probe-evidence/astra-a30d-search-baseline`
  were inspected. No topic opened or edited. This is a stale active-search binding, not another A42 diffable crash.
- Next repair contract: retain exact topmost controller/search field and current raw text/selection/focus; renew only its
  client/VM binding after same-account/actor Ready and fresh route metadata. Keep global modal guards and the existing
  quiescent replacement path. Fence queued publishers, target/error actions and awaits to their captured binding; close an
  old diffable batch's own lifetime while rejecting stale viewport/load side effects. Swap only after snapshot drain; defer
  marked input, foreign presentation and active interaction through explicit lifecycle events. Native wiring and actual
  continued typing/clearing after foreground must be checked before marking active search fixed.
