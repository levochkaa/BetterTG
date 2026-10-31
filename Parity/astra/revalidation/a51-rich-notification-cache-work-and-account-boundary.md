# A51 rich-notification cache work and account boundary — 2026-10-03

- Baseline `7002fbd`/production `d38720d`; unchanged product from final build `163857-71725-11058`. ETTrace runner/framework
  are absent, so one bounded native `sample` capture uses the existing binary with no temporary dependency or project patch.
  Audit Simulator59EB535C/iOS26.5, PID74960, launch16:41:43.101; sample starts16:41:43.211 for4s at requested1ms interval.
  Installed/product `BetterTG.debug.dylib` UUID both `C0AB6393-0C4C-3302-822B-E0934568680C`; installed bundle UUID-directory
  `037BB6D0-97E9-4552-A392-244CC9CD9041` matches the sampled executable path. First-party hot stacks have source symbols.
  Sample omits its binary-images table; retain that limit. Artifact: `.build/ui-probe-evidence/astra-a39-diagnostics/startup-sample.txt`.
- Independent full first-thread tree audit:1931 main-thread observations,8243 parsed nodes at sample lines24–8266;
  disjoint notification sinks628/1931=32.5% (chat418,user210). Inside those628: normalize/decode/JPEG266; atomicwrite197;
  cache URL/AppGroup/directory lookup139; source Data read19; other7. Do not add nested inclusive counts. UIKit accessibility
  startup381/1931=19.7% and earlier dyld bootstrap182/1931=9.4% are separate branches. Sample weights include waits and are
  not CPU milliseconds; instrumentation, startup/cache/network state and AX activity limit timing claims.
- Same-PID report16:41:47/container `72E59F99-2256-47EA-A19B-AC074DA6EA0F` fails A39 deadline. Motion wait0.520s;
  completion maxGap0.532s. Last verifier arrives2.271s for display timestamp1.645s; deadline2.293s. Target is mounted/visible
  at0.167pt residual after two corrections, without the final pair of observations. This correlates cache work and delayed
  delivery in one launch; it does not prove a sole cause or quantitative speedup. Full report: `startup-profile-probe.txt` nearby.
- Source: `RichNotificationCacheCoordinator.swift`30–41 receives raw TD updates on main;74–93 performs placeholder/full-avatar
  normalization/write and loads completed files before checking registered references. Each unrelated completed file may
  therefore be read. Refresh/media closures reuse global `td` across awaits. `RichNotificationCache.swift`48–62 uses shared
  peer/message keys; `NotificationService.swift`53–54 falls back to active account for an unmatched notification account.
- Bounded A51a prerequisite: require positive Telegram account-user ID for cache reads/writes, new account namespace,
  nil/mismatch fail closed, no legacy lookup/deletion. Preserve logical peer/message keys, JPEG format/dimensions and intent
  identifiers. Scoped current-source event admission and captured immutable client/account around awaits; clear file mappings
  on client replacement. NSE session/account selection must not put another account's bytes in metadata's namespace.
- Then A51b: move complete avatar jobs (source read, directory lookup, normalization and write) to a bounded serial utility
  worker, coalescing latest pending work per scoped destination. Preserve fallback/update ordering and invalidate old demand.
  Do not dispatch an unbounded block per event or move only JPEG conversion. Media work and full notification lifecycle
  remain explicit until separately covered. Preserve no-server mutation probes and before/after source/build/UUID proof.
- Adjacent baseline findings: avatar file mappings retain superseded same-account photos; source namespace alone does not
  provide photo-version ordering (A51b below repairs this map). NSE's unmatched-message fallback and unstructured resolution task/expiry
  ownership are A52, outside the cache-namespace prerequisite. Do not label this flow fully account/lifecycle-verified.
- Telegram references: official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`467–491 uses
  the selected account's MediaBox cache,855–880 selects notification account by payload key,902–934 keeps state on its queue.
  Pre-Liquid `8e7e5fe` same path459–483/785/849–872 retains account cache/queue behavior. Adapt contracts only; no MediaBox,
  Postbox or SignalKit copied. TDLibKit `1.5.2-tdlib-1.8.66-022d6020` models/APIs remain unchanged.
- A51a fix `84baa09` (worker `8922c6d`, exact reviewed tree `e07df0d`): all avatar/media cache callers now require a positive
  Telegram user ID; disk paths use `RichNotifications/accounts/<userID>`, without changing logical peer/message/Intents keys.
  NSE selects only an exact metadata-account match. Five coordinator TD update sinks use scoped publication, capture the
  original client and recheck source/account/client after awaits; completed files are read only when references exist.
  Reference maps reset on client generation change. Invalid scope exits before lazy container resolution. JPEG contracts remain.
- Worker joint six-file SwiftFormat and build `170232-12469-13006` pass. Primary integration build `170800-18896-18037`
  passes10s; complete log has zero warnings/errors (success at line1560). Independent peer reviews the exact tree; no unrelated files included.
- Native isolated probe at `84baa09`: Audit Simulator59EB535C/iOS26.5, PID19449, fresh container
  `2466B327-A10B-4455-814E-5AB9A0A10601`, report17:08:34+04. `-ui-probe-notification-cache-scope` passes actual JPEG/cache IO
  in a UUID temporary root, exact red/blue avatar/media bytes for colliding IDs across accounts, nil/0/negative zero resolver
  calls, no legacy fallback or mutation of130 legacy media entries, queued scoped publication, independent wrong-client/user
  negatives and reused file IDs after account/client replacement. Fixture RPC/account-store writes=0; owned fixtures are removed.
  Report: `.build/ui-probe-evidence/astra-a51/cache-scope.txt`. Actual coordinator delayed RPCs, NSE delivery/expiry, media task
  bounds and main-thread relief are unverified. No performance claim belongs to this prerequisite.
- Planned bounded slice (implemented below): A51b serial utility avatar worker with bounded/coalesced pending jobs, current-photo reference replacement,
  and same-photo candidate quality ordering. Entire read/normalize/path/write must leave main; no unbounded dispatch block per
  event or main-contended lock held during disk IO. Keep account/client invalidation and fail-closed cache scope. Then one
  comparable startup capture, with cache/startup variance retained; A52 and actual queued ChatView proof stay open.
- A51b design boundary before implementation: one active job and at most128 pending scoped destinations; revoke on synchronous
  authorization invalidation as well as source replacement. Success-only bounded dedupe must allow failed writes to retry.
  Generation checks can reject work before publication, but an already-entered atomic write may finish in its captured account
  namespace. Serial order prevents an older app job overwriting a newer app commit; strict no-write-after-NSE-handoff needs
  a separate drain/versioned-publication contract. Media IO, task/RPC lifetime and full NSE correctness are outside this slice.
- A51a checkpoint build `171052-22021-9011` passes4s, full1385-line log zero warnings/errors. AGENTS/CLAUDE remain identical;
  prohibited production/dependency marker scan is empty. Goal remains active; next implementation is the bounded A51b slice.
- Pre-A51b paired baseline after the namespace change: source `e87ab66`/production `84baa09`, same final build above,
  same Audit Simulator and only `-ui-probe-viewport-authority`; PID24933. Launch17:12:53.045+04, sample17:12:53.148 for4s/1ms.
  Installed bundle `B0BB3B10-B68A-4673-B618-4B2A7AB72BED` matches the sample path; installed/product debug-dylib UUID both
  `067931AE-7CD7-3FA2-8EC6-92061BAFD04F`. Main-thread observations2288; symbolicated cache stacks remain. Binary-images
  table is again unavailable. Same-PID viewport report17:13:01 passes, which further limits any sole-cause claim about the
  earlier deadline failure. Container `2DCEB9EF-3155-42B7-8A65-D5A1538AF1A9`; saved `avatar-baseline-sample.txt` and
  `avatar-baseline-context.txt` under `.build/ui-probe-evidence/astra-a51`. This run exists to separate the upcoming worker
  change from account-namespace/cache warm-up; it is not a statistically controlled latency benchmark.
- Independent baseline tree audit:8340 nodes at lines24–8363, exclusive sum2288 with no negative nodes. Disjoint user/chat
  cache subtrees994/2288=43.44% (user412,chat582). Within994: atomic Data.write352; normalization/ImageIO/JPEG334;
  URL/AppGroup/directory277; source reads21; protection attributes1; other9. Avatar descendants993 and sink totals999 overlap
  this count and must not be added. Whole-main top leaves include mach_msg2_trap448 and __ulock_wait2 387; waiting is included.
- A51b fix `54872bc` (worker `3226fc7`, exact independently reviewed tree `8e4a1f17`): one serial utility drain, at most128
  pending peer batches with up to3 ranked candidates each, and256 success receipts. Main submits immutable metadata/paths;
  source reads, cache-directory lookup, image decode/JPEG, atomic writes and protection attributes run on utility. Pending
  overflow drops oldest best-effort prewarming. Locks cover metadata only, never IO. Failed high-rank candidates fall back
  to small/placeholder; successful quality survives receipt eviction, and failed writes remain retryable.
- Current photo revisions replace old reverse file references and reject held stale work. Authorization nil synchronously
  invalidates pending jobs, including TDLib handoff without activeClientChanges. Same-account client replacement gets a new
  generation. Refresh request UUID plus per-peer photo-change sequence rejects superseded same-source getChat results, also
  when a newer user-photo admission replaced that destination; unrelated peers do not invalidate it.
- Worker joint five-file SwiftFormat/build `172444-41649-30775`: PASS8s, full1458-line log zero warnings/errors. The earlier
  `172139-37803-1252` Gate Sendable warning was repaired by auditing all mutable gate state under lock/semaphore; it was
  not suppressed. Primary integration build `172737-45171-21885`: PASS13s, complete log zero warnings/errors, success1572.
- Native combined cache-scope/worker probe at `54872bc`: PID46367, Audit Simulator59EB535C/iOS26.5, fresh container
  `8E662CBF-C9BE-4180-9EE7-08995B18DB99`, both reports17:28:19+04 PASS. Actual isolated JPEG/filesystem work covers100-offer
  coalescing, one held active job, bounded pending/receipt eviction, quality after receipt eviction, old-photo and source-ABA/
  client-replacement rejection before write, exact fresh bytes, missing-big→small and corrupt-big/missing-small→placeholder,
  all-candidate write failure and retry. Container resolution rejects main-thread access in the worker fixture; synchronous
  worker IO remains on its utility queue. Cleanup revokes/drains owned workers before removing only their UUID fixture root.
  This does not exercise real delayed coordinator TDLib RPCs or NSE delivery. Saved `avatar-worker-native.txt` nearby.
- One post-worker startup capture uses the same wrapper/probe flag and4s/1ms request: PID49173, launch17:29:11.408+04,
  sample header17:29:11.710. Bundle `11D7EF11-4A25-4D73-83FC-7EF5F6A80FBE`; installed/product/sample binary-table UUID
  `BE0DFC28-05EE-374C-B849-264D354E5831` agrees. Main3174 observations are all idle mach_msg2_trap; no avatar-worker/cache
  stack appears on any thread. This capture lacks equivalent active work and cannot prove994→0 improvement, source-level
  startup speedup or actual production avatar-job execution. Attach/setup timing and warm state remain uncontrolled.
  Same-PID viewport report17:29:17 PASS in container `4E37FF80-13B4-4E3E-B298-072A084EAC18`; no deadline was relaxed.
  Artifacts: `avatar-worker-sample.txt` and `avatar-worker-profile-context.txt` nearby. Align a future measurement with actual
  production job start/end receipts before claiming a before/after performance result; do not repeat blind launches.
- Remaining A51: current-source per-peer registration metadata is uncapped; photo removal revokes jobs but leaves the previous
  JPEG on disk; already-entered atomic write may finish after handoff. Media IO/task bounds and A52/A53 are unchanged.
  Source/native-worker evidence supports this bounded avatar repair, not complete notification correctness or A39 causality.
- Independent post-profile audit confirms114 call-graph nodes/10 threads, no negative exclusive weights, main entirely
  idle; launch-to-header delay302ms versus baseline103ms does not establish active-window alignment. No further capture or
  user-cache deletion was attempted. Future profiling needs content-free production job receipts before a matched capture.
- Final A51b checkpoint build `173407-60281-18514`: PASS5s, full1385-line log zero warnings/errors. AGENTS/CLAUDE match;
  prohibited production/dependency marker scan is empty. Worker checkout is clean, all implementation changes are committed;
  only this ledger awaits its focused commit. Goal remains active; A53 is the next bounded implementation.
