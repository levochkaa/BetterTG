# A23c forum-topic delivery — 2026-10-02

- `3be0eb5` routes all eight ForumTopicsVM typed subscriptions through the existing `ChatUpdateDeliveryAuthority`. Queued old
  account/client updates cannot mutate current same-ID topic info or start a current-client refresh; unscoped events are rejected.
  Captured chat/topic and current-owner gates remain. Pagination/topic read starts now recheck context before issuing the captured
  RPC; existing post-await generation/context guards remain. No UI, cursor semantics, query order or storage format changes.
- References: current/pre `ChatListUI/Sources/Node/ChatListNode.swift` immutable account context at 1216/1213 and
  `chatListViewForLocation(...account:context.account...)` at 1934/1939. TDLib pinned `ForumTopicInfo` and generated
  updateForumTopicInfo/updateForumTopic/message content/edit/delete/send models, `getForumTopics/getForumTopic`.
- Two Swift files formatted together; `.build/logs/xcodebuild/build-Debug-20261002-193919-80905-8514.log`: PASS8s, zero warnings.
  Audit Simulator source `3be0eb5`, PID `81496`: expanded `-ui-probe-chat-update-delivery` passes actual generated topic-info
  dispatcher plus production observer admission for queued A→B, colliding chat/topic IDs, replacement client, missing source,
  another chat and retired owner. Root authority, text spoilers and Chat restoration-state regressions pass in
  `.build/ui-probe-evidence/astra-a23-forum-primary`.
- Probe isolates subscribers/owners; it does not construct ForumTopicsVM, send server mutations or switch real accounts.
  Actual topic-list UI and delayed server RPC ordering are unverified. Auth/static-image subscribers, same-epoch read ordering
  and A30 ForumTopics route replacement remain separate work.
