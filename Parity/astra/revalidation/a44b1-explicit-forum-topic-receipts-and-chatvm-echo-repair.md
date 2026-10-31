# A44b1 explicit forum-topic receipts and ChatVM echo repair — 2026-10-03

- Worker `3e5f529` integrated as `8040628`, independently reviewed. Exact positive `.messageTopicForum` route/account/client
  consumes its own updateForumTopic outbox watermark. Canonical raw message topic and chat must match; other topics, numeric
  collisions with saved/direct/thread kinds and missing topic identity cannot borrow it. Pending/Failed precedence stays intact.
  All-messages aggregation remains unimplemented; neither chat-global nor nil-to-General fallback was added.
- Subscribe before the reused fresh getForumTopic baseline, even with restored metadata. Receipt UUID/revision, exact returned
  info.chatId/forumTopicId, current source and request-owner UUID fence completion/cleanup. Initial readonly loading cannot start
  a duplicate request. Restored ForumTopic/history is not receipt authority; source departure cancels and terminally retires it.
- Review found the existing scalar observer refetched after every update, including TDLib's own getForumTopic response echo.
  ChatVM now consumes direct scalar/draft payload, preserving omitted info/lastMessage/order/unreadCount; only a changed inbox
  edge requests the omitted unread count once. Identical/outbox/draft echoes do not fetch. Later accepted scalar/draft (including
  nil clearing) overlays a late full response; separate info revision preserves newer info. Composer dirty/revision policy remains.
  This does not repair the independent ForumTopicsVM list cycle, tracked as A45.
- References: TDLib022d6020 `td_api.tl:2980–2992,10539–10552`, `ForumTopic.cpp:48–54,137–160`,
  `ForumTopicManager.cpp:617–636,831–880,1180–1190`. Official current6ad963e5/pre8e7e5f:
  `TelegramCore/Sources/State/AccountViewTracker.swift:1931–1959/1873–1901` and
  `Postbox/Sources/MessageHistoryView.swift:1155–1210,1364–1376/1128–1183,1333–1345` use exact-thread read state,
  with no global fallback for absent thread data. No upstream infrastructure imported.
- Native PID86336 `-ui-probe-message-delivery` PASS, including all A44a cases plus exact-topic/global/kind exclusion,
  duplicate-update read fence, wrong returned identity, canonical promotion, source/UUID retirement, late draft overlay/clear,
  identical echo before/after full response and changed-inbox decisions. Three actual MessageCells reconfigure only the matching
  topic status, retaining foreign/unknown rows and offset. The request-count assertions model production reducer decisions;
  they do not count whole-ChatVM or live TDLib requests. Saved result `.build/ui-probe-evidence/astra-a44-forum/`.
- Actual PID90037 on source5b9b322: existing DEBUG `-ui-smoke-forum-topic-write` only navigated to an existing writable General
  topic1; despite the flag's historical name, no text or messages were written. A pre-existing text and photo show single checks;
  three AX rows report Delivered (one is the service row whose visible status is intentionally hidden). After Home/foreground,
  ownership released05:06:29.414, restored05:07:55.499, Chat viewport settled/fresh history05:07:57.745 (+04); same PID,
  empty topic composer, same status/geometry: x8/w386, y93.3333/128.6667/563.6667, heights30.3333/391/208.
  Screenshots before/after inspected. This is route/display/source-renewal smoke, not proof of receipt freshness, peer Read
  transition, actual RPC counts, remote draft edits or forum send/retry. Native fixture covers exact watermark decisions separately.
- Six changed Swift files formatted together; primary `050253-84583-2008.log` PASS12s, worker `045916-78400-10799.log`
  PASS13s, complete logs zero warnings/errors. No data reset, focus activation or Simulator shutdown.
