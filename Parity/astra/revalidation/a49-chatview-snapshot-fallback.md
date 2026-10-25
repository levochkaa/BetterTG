# A49 ChatView snapshot fallback — 2026-10-03

- Source `9e470e4`: `ChatView.swift`1553–1559 dequeues before resolving `message(for:)` from current `chatVM.messages`.
  `messagesDidChange` defers structural apply to the main queue; visible delete adds a140ms delay after the VM removes rows.
  Thus an outgoing snapshot ID can lack a live model. The current miss returns a fresh cell; weak-owner/cast exits also need
  exact registered dequeue behavior. `ChatMessageRenderOwners` detects wrapper changes only and is not a snapshot model store.
- Reference: local UIKit26.5 `UICollectionView.h`471–473 requires reconfiguration to keep existing cells. Telegram pre-Liquid
  `8e7e5fe`, `ChatHistoryListNode.swift`4226–4241 carries the transition's history view/opaque state into its transaction/completion.
  Adapt ownership to UIKit/TDLib; no Texture/Postbox/Display import and no TDLib schema change.
- Bounded A49a plan: shared production dequeue/configure path, exact same cell on model miss, inert media/callback/selection/AX
  cleanup, normal same-ID reconfiguration recovery. Native production MessageCell/diffable probe removes only its fixture model
  while retaining its snapshot ID. No real message delete/send. A49b must separately retain outgoing models through exact apply
  completion and gate stale callbacks; A49a alone must not be reported as complete transaction ownership or a reproduced Chat crash.
- A49a `02a26b2` (worker `64727d6`, reviewed tree `a51fc2e3`) implements one shared dequeue path for message/date/topic cells.
  Missing model/owner or cast mismatch returns the exact registered object. Unavailable MessageCell resets existing media/resource
  owners, text, closures, AX, selection/swipe and owned animation presentation; date/topic headers clear text/AX/action/icon state.
  An extracted bubble is concealed without reparenting or altering its external owner's transform/alpha. Normal configure restores
  visibility, actions and accessibility. Context-menu captured actions and entire menu lifetime are outside this slice.
- Worker build `125718-22308-10102`: PASS9s; integrated `130225-28206-10571`: PASS15s, complete logs zero warnings/errors.
  Audit59EB535C/iOS26.5 PID29347 report13:03:16 FAILS the combined extraction assertion. Diagnostic-only `527c938` (worker
  `d62376af`, tree `33ba48c3`) preserves predicates; build `130540-31515-29596` PASS12s/fullzero. PID32074 report13:06:20
  establishes parent=true, hidden=true, expected transform preserved and own container identity/alpha1; only UIKit alpha getter
  `0.80000001192092896` differs from literal `0.80000000000000004`. These failures are retained, not relabeled as passes.
- Oracle-only `4da10ff` (worker `9deb556`, tree `c37e9732`) captures actual getter baselines immediately after assignment, checks
  nontrivial arming, then compares exact post-fallback equality; no epsilon/production change. Joint SwiftFormat0/7; build
  `131011-36936-10906` PASS17s, full log zero warnings/errors. PID37648 report13:10:52 PASS: native MessageCell same-object
  reconfigure without prepareForReuse, missing model cleanup, recovered same-ID text/selection/actions, released weak owner,
  extracted ownership/presentation preservation, header unavailable/recovery and cast mismatch. Existing delivery/A44 receipt,
  stable wrapper replacement/album promotion and offset checks pass. Fresh install container/report receipts are in
  `.build/ui-probe-evidence/astra-a49a-fallback/README.md`.
- Same0404996/PID37648 actual Saved Messages renders text/forward/date headers and empty composer; existing forwarded text's
  context menu opens and dismisses to the same bubble. Screenshots `saved-settled`, `menu-open`, `menu-dismissed` inspected.
  No option chosen, text typed, link opened, send or delete. This ordinary UI check does not reproduce unavailable-row timing.
  Loaded-media cancellation, suspended history pan and captured menu actions are not armed by this fixture; A49b remains open.
- A49b source contract: five producers (structural, single/bulk reconfigure, highlight, quote) must share any new scheduler.
  Preserve A22 intent/tickets/depth, A44 wrapper invalidation, delete140ms barrier, send-flight target settlement and client retirement.
  `ChatVM+Publishers`305–322 mutates an album wrapper in place; ChatVM1332–1353 can replace the same album ID's wrapper.
  Retention of mutable references alone is not a coherent rendering transaction. Keep provider rendering separate from live
  action/navigation/prefetch lookup; exclude deleting IDs from reconfigure so configure cannot revive a fading bubble.
  The provider-callback prerequisite is repaired below; rendering ownership stays separate.
