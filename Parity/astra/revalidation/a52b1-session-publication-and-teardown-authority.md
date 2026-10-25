# A52b1 session publication and teardown authority — 2026-10-03

- `a4a1e65` (worker `0f1ef47`, reviewed tree `c87a5863`) introduces one locked session lifetime for continuation,
  client bootstrap and at most one configure/process/resolve role. Tickets are reserved before spawning and reject a
  task handle arriving after completion or retirement. The target's raw chat prefilter prevents a same-messageID event
  from another chat consuming the sole resolver. Overflow is rejected before client creation; getChat type/peer checks remain.
- Outer cancellation, timeout and authorization failure retire authority once, cancel registered task handles and resume
  the result outside the lock. Late callback admission, post-await results and cache publication require live exact tickets.
  Synchronous cache writes and retirement share the lock: writes already inside it may delay retirement, but later writes
  cannot enter. Utility close is claimed once after retirement without joining pending TDLib tasks; the process lock stays
  held until close returns. Basic service cancellation checks stop already-cancelled work before lock/session/content paths.
- Telegram official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`2524–2527,2571–2606,
  and pre `8e7e5fe`2267–2270,2314–2349 separate handler disposal from once-only content completion. BetterTG adapts
  ownership to Swift tasks/TDLibKit; no SignalKit/Postbox/Display infrastructure copied. Pinned TDLib `DialogId.cpp`66–88
  and `DialogId.h`26–27 define private/basic/supergroup raw chat IDs; monoforum arithmetic remains accepted.
- Worker joint seven-file format3/7; wrapper `181538-16903-22292` PASS10s, complete1585-line log zero warnings/errors.
  Independent immutable peer review passes. Primary joint eleven-file format0/11; integration `182000-23494-22239`
  PASS17s, complete1585-line log zero warnings/errors. Worker is clean; all seven implementation files committed.
- Native at `a4a1e65`, same Audit Simulator59EB535C/iOS26.5, PID25440, fresh container
  `90A3B266-C8A0-4C49-BC66-191D96C1C1C1`: lifetime report18:21:15+04 PASS. Production authority fixtures cover cancel
  before begin/create, creation concurrent with retirement/early callback, wrong/duplicate tickets, completion before handle
  registration, three held uncooperative role tasks, result before their release, close claim without joining, positive and
  denied effects, and synchronous publication ordering. Exact admitted tasks are awaited; positive event receipts are checked.
  No actual TDLib client/cache/account/notification/donation effects in this lifetime probe.
- Same run: target, media-admission and cache-scope reports18:21:14 PASS; avatar worker18:21:15 PASS. Target adds exact
  group-chat, monoforum and overflow checks. Cache/worker tests retain real isolated JPEG IO. idb hierarchy available before
  install; wrapper kept Simulator in background. Evidence: `.build/ui-probe-evidence/astra-a52-a53/lifetime/`.
- Limits: pinned SDK RPC continuations can outlive cancellation; close is not a callback-drain proof. Check-before-await
  cannot guarantee zero new RPC submissions after a concurrent retirement, while publication itself is strictly gated.
  Actual NSE/APNs/SDK shutdown remain unverified. An entered synchronous write can delay expiry; no hard-deadline guarantee.
- Next A52b2: bind service processing task, content handler, temporary attachment/INInteraction construction and completion
  to one request authority. A Task.isCancelled check before builder alone has a check→side-effect gap. Preserve original
  fallback and once-only delivery; test replacement, expiry before task-handle registration, late producer and positive delivery
  through a production seam without donating synthetic interactions. Do not conflate this with the session-only repair.
- Then A53b: explicit hidden/showPreview denial must revoke even a previously accepted in-flight resolver for that same
  message; the new single resolver does not make its first notification permanently authoritative. Full-message eligibility,
  known content/delete revisions and versioned persisted evidence must govern cache/builder/wait paths together.
- A52b2 plan reviewed at `7b55953`: a request coordinator owns one UUID, original fallback, handler and task handle.
  Replacement retires the exact old record; cancel and handler delivery run outside the lock and may reenter begin.
  Every later install/check/finish must therefore validate its ticket, including the ticket returned by an outer begin.
  Finish invokes its synchronous content producer under the same lock as expiry, then retires and delivers its captured
  handler once. Preserve ordinary content generation, original fallback and account/session selection. Test actual
  coordinator paths with injected effects; do not donate synthetic interactions. Entered builder IO may delay expiry;
  only donation invocation is fenced, not completion of an already-started system donation.
- Final checkpoint build `182318-27788-15437`: PASS5s, complete1385-line log zero warnings/errors. Production/dependency
  prohibited-marker scan empty; AGENTS/CLAUDE match. Primary implementation and worker are committed and clean; this
  proof ledger is the final focused documentation commit. Goal stays active; next implementation is A52b2 above.
