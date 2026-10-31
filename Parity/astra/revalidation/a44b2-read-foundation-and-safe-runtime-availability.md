# A44b2 read foundation and safe runtime availability — 2026-10-03

- Source at `f5b9dfb`: all-messages `refreshForumTopic` starts one task per topic without a concurrency bound, retains its VM
  across await and publishes returned metadata without checking raw chat/topic identity. Adding an independent receipt queue
  would duplicate those reads. First share and bound this metadata path; retain exact timeline/composer demands, protect live
  scalar/info changes, retire on source departure and count canceled-but-unfinished TD calls until their actual completion.
  Per-topic receipt rendering follows separately. General remains only an explicit composer demand, never a receipt fallback.
- Exact Telegram reference: `6ad963e` `Postbox/Sources/MessageHistoryView.swift`1155–1217,1364–1374 and pre-Liquid
  `8e7e5f`1127–1188,1333–1343 collect loaded messages' exact thread IDs, prune departed IDs and default missing per-thread
  watermark to unread. Adapt the contract only; no Postbox dependency. TDLib `022d6020`: `getForumTopic`, `updateForumTopic`,
  `updateForumTopicInfo`, exact `Message.topicId`; cached display metadata is not fresh receipt authority.
- DEBUG-only `-ui-smoke-forum-all-messages` selects only a naturally base-mode forum from loaded folders with zero unread
  messages/mentions/reactions/poll votes and no marked-unread flag. It rechecks raw getChat/getSupergroup identity, current
  account/client, attached top controller and the exact current row object before navigation. At most eight candidates are
  read serially. A source-departure token and 15s watchdog revoke late navigation; the watchdog does not cancel TD transport.
  No forced viewAsTopics override, synthetic chat, mode toggle, send or scheme change. Independent source review passed.
- Native availability result on the logged-in audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5, PID5126,
  source `f5b9dfb` plus this DEBUG delta: fresh06:12:31 (+04) result has `loaded-forums=9, eligible=0`; no route opened.
  This is a blocker for live all-messages smoke in the loaded safe candidates, not proof of account-wide absence. Before/after
  bounded idb type counts remain22 elements; no personal message text was dumped. Evidence:
  `.build/ui-probe-evidence/astra-a44-all-messages/forum-all-messages-route-probe.txt`. Do not claim reader/receipt success
  from this availability check; their controlled production-component proofs and integration remain the next implementation.
- MainView.swift formatted in one invocation; primary061118-3495-7982 PASS26s, full log zero warnings/errors.
