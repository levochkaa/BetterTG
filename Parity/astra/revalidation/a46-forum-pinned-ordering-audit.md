# A46 forum pinned ordering audit — 2026-10-03

- Source `ebdb3bf`: `ForumTopicPageState.merging` and `ForumTopicsVM.sortTopics` compare only order and topic ID;
  `ForumTopicCell` renders pin decoration/background without moving the row. A pinned topic with an older chronological
  order can therefore remain below an ordinary topic. This predates A45a's direct scalar path.
- Pinned TDLib022d6020 `ForumTopic.cpp:117–133` derives order only from last message and draft date. `td_api.tl:3917`
  exposes isPinned separately; getForumTopics is a temporary server-list API with an explicit raw pagination cursor.
  Telegram `6ad963e`/pre-Liquid `8e7e5f` `ChatListNodeLocation.swift:365–388`/`264–288` uses a separate pinnedIndex.
  `ForumChannels.swift:1265–1313`/`1075–1122` stores pinned thread IDs separately when applying loaded results.
- Preserve configured pin order, exact source/query ownership and raw cursor; do not infer pin positions from timestamps
  or topic IDs. Pinned `ForumTopicManager.cpp:748–774` consumes the server's ordered pinned IDs only as membership and
  emits an update only when isPinned changes; a pure remote reorder has no exposed position update. Preserve server-head
  response order where available and state the refresh limitation rather than inventing a local order. No server pin writes or
  runtime reordering were exercised; this is a gap queued after A45, not a completed parity claim.
- Actual PID36808 on 80b070b confirms the visible defect: pinned General/topic1 is third, below two ordinary topics, both before
  and after search/foreground/Cancel. Screenshot `astra-a45-topic-updates/list-before.png` and list-after were inspected;
  no pin mutation was issued. Multiple configured pin ordering still has no runtime proof.
- A46a repair boundary: primary topic list only. Keep a query-owned display rank from the accepted raw zero-cursor server
  page, separate from chronological order; append and individual reads cannot assign configured rank. Preserve it while a
  same-query head refresh is pending or fails; clear on query change and transfer only matching-query restoration seeds.
  Newer pin-membership transitions must fence an older head's rank, including accepted individual full reads; equal echoes
  must not invalidate rank. Keep raw cursor, A45 full-read/fuzzy arbitration and A47 transport bounds unchanged.
  Unknown/re-pinned rank waits for explicit head refresh rather than fabricating pin position; remote position-only changes
  have the TDLib limitation above. Shared merge defaults and the forwarding topic selector remain a separate A46b follow-up.
  Plan: four files plus real-VM head/append/unpin/re-pin/query/restore/late-head regressions; source-confirmed ordering does not
  establish actual multi-pin/viewport behavior. A46 remains partial until remaining consumers and update behavior are addressed.

- Integrated A46a `ec987de` (worker `518feb8`), independently reviewed tree
  `3613000505747ce3eee4dc0b979739dca64965da`. Query-owned `ForumTopicPinnedOrder` uses eligible exact-chat raw head IDs;
  non-head reads cannot assign rank, membership edges invalidate older tickets, and display restoration carries matching ranks.
  Shared chronological merge and forwarding selector remain unchanged. An initially unknown pin echo is admitted, but a known
  unpinned→pinned echo during a head read is indistinguishable from a concurrent change: it conservatively requires a second
  explicit stable head. No automatic pin-fetch loop or invented position is introduced.
- Integrated SwiftFormat0/4; primary `build-Debug-20261003-110934-87641-16429.log`: PASS15s, full log zero warnings/errors.
  Native PID88745 on `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone17Pro/iOS26.5, fresh forum-updates report11:10:15+04:
  PASS raw head order against chronology/ID, duplicate pin, append/individual preservation, unpin/re-pin, failed head, query and
  display seed, initial/equal/changed echo, scalar/individual membership races and source ABA. Existing A45/A47 cases also pass;
  exact injected native-task terminals are awaited, not evidence of real RPC timing or global transport bounds.
- Existing native restoration/snapshot regressions PID92263 (11:12:37/39) and active-search PID92585 (11:13:32) pass.
  Actual read-only forum list baseline on 66c4a78/PID84938 reproduced IDs153,196,1,134,94,37 with pinned General third.
  After `ec987de`, PID92862 shows1,153,196,134,94,37: General first at y116, row61.33pt, width402pt.
  `astra-a46-pinned-order/after.png` was inspected. No pin changes, topic selection or forwarding; native Back/search islands
  remain A32. Controlled multi-pin ordering is proven; live configured multi-pin changes and scrolled prepend/resize are not.
  Same PID92862 Home→foreground keeps the exact order/frames, with `ForumTopics client restoration: replacement accepted`
  at11:16:16.793+04. This proves one quiescent display-rank renewal on that loaded list, not active remote pin mutation.
- A46b before proof: actual PID92862, still `ec987de`, opened an existing photo's Forward action → searched the existing forum
  → entered its production topic selector. IDs153,196,1,134,94,37 put pinned General third at y290.67pt (first rowy168).
  `astra-a46-pinned-order/forward-topics-before.png` was inspected; no topic/destination selected and no Send.
  Reference: Telegram current/pre `submodules/TelegramUI/Components/PeerSelectionController/Sources/PeerSelectionControllerNode.swift`
  223–249/196–222 uses the shared forum ChatList and its separate pinnedIndex. After A48, reuse the query-owned pin projection
  in this consumer: accepted raw head assigns rank, append preserves it, accepted membership edges invalidate obsolete positions,
  and changed query clears it. Keep raw cursor, server query membership, A48 snapshot/selection gates and existing rights semantics.
  Native consumer checks must cover ordered pins, append/unpin/re-pin, query changes, failed head retry and unchanged selected IDs.
- A46b integration `a9ffd99` (worker `72a8ee5`, independently reviewed tree `7f78bf8a`) reuses `ForumTopicPinnedOrder` in
  the production Forward controller. Exact-chat/positive incoming rows are merged before projection; raw response cursor/hasMore
  remain untouched. Only accepted raw head assigns ranks. Append observes known membership edges, including duplicate-ID edges
  within its page, without inventing rank; query change clears rank. A48 model/apply/selection/source/containment gates remain.
  Single SwiftFormat0/2; integrated build `build-Debug-20261003-120434-2571-25802.log`: PASS22s, full log zero warnings/errors.
- Native PID14782 on audit59EB535C/iOS26.5, fresh report12:07:44+04: PASS ordered two-pin head, invalid/foreign/hidden rows,
  reversed append order/raw cursor, across-page unpin→re-pin revocation, selected-ID persistence, failed head retry/new query
  and existing A48 transaction/teardown cases. Same-page duplicate ABA is source-inspected, not separately native-tested.
  This run's post-completion teardown receipt was already retired; the earlier PID68845 proof remains the explicit pre-retirement case.
- Actual PID15841 at `a9ffd99`: existing photo → Forward → existing forum → production topic selector now shows
  IDs1,153,196,134,94,37. General1 is pinned and first at y168pt instead of third at y290.67pt; rows remain402×61.33pt.
  `astra-a46-pinned-order/forward-topics-after.png` inspected. No topic/destination chosen, pin mutation or Send. This is actual
  single-pin loaded-list proof; live multi-pin editing/reordering, permissions and delivery remain unverified.
