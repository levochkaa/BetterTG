# A45 forum fetch-response echo audit — 2026-10-03

- Source `c18b52c`: `ForumTopicsVM.swift:281–286` invokes refresh for every scalar topic update;341–365 cancels/replaces its
  task then calls getForumTopic, without an in-flight skip or semantic dedup. The pinned TDLib022d6020
  `telegram/ForumTopicManager.cpp:831–880` executes the user query, and1165–1190 replaces its topic and unconditionally calls
  `send_update_forum_topic` (including the literal `topic_ == nullptr || true` branch). Thus an unchanged response can provoke
  another request. Independent reviewer and primary confirmed this; request-count/runtime impact has not been measured.
- A44b1's ChatVM loader has the analogous edge and must break it before receipt baseline integration. The list owner is a
  separate slice: consume scalar fields directly, preserve fields absent from update (lastMessage/order/unreadCount/info),
  reconcile only true semantic changes requiring a read, and revision-fence stale full responses. Preserve query, pagination,
  current-client authority and stable topic rows. Prior A30d restoration proof does not cover or repair this cycle.
- Additional pinned-source evidence: `ForumTopicManager.cpp:930–961` emits the same update for every page row before
  getForumTopics resolves; `ForumTopic.cpp:117–133` derives order from both lastMessage and draft date. A45a must suppress/coalesce
  page-created unknown demands, refresh omitted count/order only for relevant semantic changes, and overlay exact-topic scalar
  events accepted after either page or individual dispatch. Full page-vs-individual ordering of omitted fields and later
  hidden/renamed-info resurrection are separate A45b. Reset must preserve raw TD pagination cursor semantics and exact owners.
- A45a `80b070b` (worker `a5ea69f`) consumes known scalar payloads directly and deduplicates unchanged echoes. Unknown
  lookups coalesce behind page/individual work; a returned page satisfies only unknown-echo demand, never later semantic
  demand for omitted count/order/lastMessage. Independent review caught and repaired that demand-loss race before integration.
  Inbox/draft changes refresh once; post-dispatch exact-topic scalar updates overlay either response. Individual requests
  validate UUID/generation/query/raw returned chat+topic and use weak VM ownership across await. Synchronous source departure
  permanently retires tasks/subscriptions/leases; late cleanup cannot remove a successor. Shared applying(update:) preserves b1.
- Native PID31180 on source 80b070b, `-ui-probe-forum-updates`, PASS: actual ForumTopicsVM with controlled async read closures
  and local scoped notifications proves page/individual echo counts, unknown/failed/filtered demand, direct scalar delivery,
  post-dispatch scalar overlay/raw cursor, semantic demand across page and individual completion, wrong result identity,
  late query/error cleanup and terminal source ABA. A mounted production ForumTopicCell updates from its topics publisher.
  This is not a full diffable-controller/viewport proof or live TDLib RPC counting; no global account mutation or server writes.
- Native PID32832 on the same source: active-search and restoration probes both PASS, covering the production search controller,
  field/table/snapshot lifetime, renewed bindings, late metadata, source/account guards, saved page/query/cursors and viewport
  helpers. These fixtures do not prove current live-server filtering or a real foreground cycle. Results are saved under
  `.build/ui-probe-evidence/astra-a45-topic-updates/` with the A45a probe output.
- Native PID34729 message-delivery regression PASS, including explicit-topic scalar extraction, echo decisions, late drafts,
  real MessageCells and stable owner/offset behavior. Whole-ChatVM and live peer-read transitions remain outside that fixture.
- Actual PID36808 on 80b070b: six real topic rows loaded, search reduced to topic1, same-process Home/foreground preserved the
  raw query and focused keyboard. Ownership released05:32:58.246, restored05:33:47.182, search binding accepted05:33:47.532 (+04).
  idb physical-keyboard input produced a Cyrillic-layout query despite visible English keys; this was observed, not labelled
  literal-General proof. Screen-keyboard input and its visible correction then produced General. Cancel restored all six IDs
  `[153,196,1,134,94,37]` at their original x0/w402, y116+61.3333n geometry. Screenshots before/search/foreground/after inspected.
  No topic selected, message sent or pin changed. This verifies bounded live read/filter/renewal/navigation, not RPC counts,
  delayed server response ordering, large-page pagination or remote topic edits. Existing native Back/Search styling gap remains A32.
- Five changed Swift files formatted together; primary `build-Debug-20261003-052515-30443-1717.log` PASS11s and worker
  `052305-27973-17007.log` PASS8s, complete logs zero warnings/errors. Source review passed on immutable a5ea69f.
  A45b now addresses older full responses overwriting a newer accepted row and page responses resurrecting hidden/renamed rows;
  it must preserve raw cursors, accepted-update overlays, semantic demand and the no-echo contract.
