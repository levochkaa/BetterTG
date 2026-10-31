# A47 topic-list individual read fan-out — 2026-10-03

- Primary and independent source review at `b884159`: `ForumTopicsVM.swift`339–344/421–429 registers distinct unknown
  same-chat topic updates; 460–501 drains every pending ID and starts individual reads without a shared outstanding limit.
  Reset229–234 cancels then drops task registrations, although a TDLib await need not finish on Swift cancellation. Rapid query
  generations can therefore overlap old and new native work. This is separate from A45's fixed per-ID echo loop.
- Natural trigger: pinned TDLib `022d6020` `td/telegram/MessagesInfo.cpp`28–79 consumes topic infos from message/history/search
  responses; `ForumTopicManager.cpp`1139–1148/1358–1375 publishes changed infos. A covered topic-list controller retains its
  same-source subscription until removal (`ForumTopicsViewController.swift`145–150). An empty-query list accepts these new IDs;
  `ForumTopicManager.cpp`831–847 dispatches a network getForumTopic for ordinary user clients even when info is cached.
  Normal getForumTopics page echoes are usually satisfied by the accepted page303–305; do not attribute fan-out to every page.
- Repair boundary: bound actual outstanding individual reads, including canceled-but-unfinished predecessors; coalesce demand,
  preserve exact request/source/query ownership, raw page cursors, A45 ordinal/scalar/info overlays and known fuzzy membership.
  Any cache pruning must retain row/pending/inflight/tombstone authority. Current maps grow within a query and clear on reset or
  retirement; this is not evidence of a cross-account or permanent leak. No new backend, navigation policy or pin-order change.
- Reference: Telegram current `6ad963e` and pre-Liquid `8e7e5f`, `submodules/TelegramCore/Sources/ForumChannels.swift`,
  finite getForumTopics limit/cursor response ownership; A44b2a's loaded-topic reader supplies an existing BetterTG cancellation
  ownership pattern. A specific concurrency limit is a BetterTG adaptation, not a claimed upstream value.
- Planned proof: controlled real ForumTopicsVM burst outside a partial/failed page, maximum outstanding count, fair coalesced
  draining, repeated query reset with uncancellable old completions, source retirement and all A45 regressions. No live lag,
  OOM, request-count or server mutation proof yet. Queue after A30h and before P2 A46.
