# A44b2a bounded all-messages metadata reader — 2026-10-03

- Worker `e851373` integrated as `25f6f56`. `ChatForumTopicReads` owns at most two outstanding reads, including canceled
  TD continuations until they actually return. Exact entry/request UUID and raw returned chat/topic guard same-ID re-demand;
  weak captures let the owner deallocate during an uncancelable read. Source/composer-transfer retirement is terminal and
  clears metadata synchronously. Existing controller-pop draft save can retain permission metadata until VM teardown.
- Demand includes all canonical raw album members, General as an explicit composer reason, reply/edit, frozen voice/video
  recording and pending/outgoing drafts. A one-main-turn reconciliation handles callers that request before assigning context;
  expired reasons and unused cache entries are pruned. Typed forum admission checks matching supergroup identity and excludes
  channel/direct/saved routes. One controller hook forwards its existing frozen video topic; b1 explicit-topic path is unchanged.
- Existing scalar reducer rebases post-dispatch updates; per-entry info revision protects newer name/closed/hidden metadata.
  Predispatch cache cannot overrule a subsequent full read. Scalar/info echoes do not fetch. Failed/malformed reads remain held
  under unchanged demand; existing user refresh/Ready, explicit composer request or drop/re-add can retry. Failure does not
  starve the queue. No timer retry; scalar payload does not refresh omitted unreadCount/order/lastMessage. Existing consumers
  use topic info for headers/permissions; exact-topic receipt authority is the next b2b slice, not inferred from this cache.
- Native PID22721 on `25f6f56`, audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5: fresh06:28:59 (+04)
  `forum-topic-reads-probe.txt` PASS production reader/demand builder under cancellation-insensitive controlled continuations:
  max-two outstanding calls, coalescing, pruning/re-demand, canonical album/exact raw identities, late scalar/info overlay,
  malformed replies, failure hold/progress/explicit retry, retired source ABA and weak owner release. Terminal replies are
  matched by topic ID rather than assuming Task start order. The fixture explicitly invokes retire; actual source subscription,
  whole ChatVM, pop draft persistence, header/viewport and live TD RPC behavior remain source-reviewed or unverified.
- Same PID's fresh `message-delivery-probe.txt` PASS ordinary/explicit-topic reducer and actual MessageCell regression,
  canonical promotion, stale wrapper rejection, batched stable-ID update and unchanged native fixed-row offset. It does not
  prove b2b all-messages ticks or live peer-read transitions. Evidence files preserved in
  `.build/ui-probe-evidence/astra-a44-all-messages/`; earlier safe live availability remains blocked (nine loaded forums, zero candidates).
- Immutable independent review PASS. Six Swift files formatted together; primary062812-22030-25473 PASS19s, worker062426-17963-24832
  PASS7s, full logs zero warnings/errors. Earlier worker062209 emitted one DEBUG WeakMutability warning, fixed without suppression.
