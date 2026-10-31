# A47 bounded individual reads: integrated proof — 2026-10-03

- `80da255` (worker `e10bd0f`, reviewed tree `af57d4c`) separates the UUID-keyed outstanding transport registry from
  current-query topicID ownership. Canceled predecessors keep their slots until their exact tasks return. Each terminal
  removes only its UUID; a same-ID successor retains its authority. Current demand is a unique FIFO, duplicate reasons only
  upgrade semantic invalidation, and pages can satisfy only nonsemantic demand. Dispatch rechecks latest hidden/query
  membership and captures its read stamp/name then. A45 ordinal/scalar/info overlays and raw page cursor remain unchanged.
- Native PID97812 on audit59EB535C/iOS26.5, fresh report07:19:33+04: `-ui-probe-forum-updates` PASS. Real ForumTopicsVM
  with cancellation-insensitive injected continuations proves maximum two outstanding individual reads, 11 dispatched IDs
  after partial and failed pages, FIFO/coalescing, hidden queued veto, error/foreign-result slot release, two query resets with
  old slots still occupied, same-ID old cleanup versus successor, and source ABA retirement. Exact Task.value joins verify
  callback completion; all previous A45 checks pass too. Before-change baseline PID95173 also passed at07:15:58.
- Integrated supplementary regressions PASS: PID99039 restoration/snapshot at07:20:36/39, PID99673 actual active-search
  controller at07:21:30. The first supplementary launch used an unrecognized search argument; no search proof is attributed
  to it. The separate active-search launch used the verified flag. Evidence: `.build/ui-probe-evidence/astra-a47-forum-reads/`.
  These remain controlled native proofs, not real TDLib request counts, live foreground, server filtering or measured lag/OOM.
- One two-file SwiftFormat invocation after integration made no changes. Worker build `build-Debug-20261003-071551-95012-24969.log`
  PASS11s; primary `build-Debug-20261003-071859-97295-17064.log` PASS10s; full logs zero warnings/errors. Independent review
  passed. Queue has one record per distinct current-query demand and clears on reset/retire; no hard memory bound is claimed.
  Page requests and distinct VM instances do not share this limit. A46 remains a separate ordering repair.
