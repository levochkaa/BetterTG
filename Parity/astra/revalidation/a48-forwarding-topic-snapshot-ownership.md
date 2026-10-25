# A48 forwarding-topic snapshot ownership — 2026-10-03

- Source `ec987de`, `ForwardForumTopicsViewController.swift:205–212,288–331`: cell provider reads latest `topics`,
  falling back to a newly created cell on a miss. A page replaces that array and clears `loading` before an animated apply;
  a subsequent accepted query/page may replace it again while UIKit still reconfigures the previous snapshot.
  Reachable sequence: settled [1,2] → accepted [1,3] reconfigures1 → accepted [4] before completion → older provider asks1.
  RPC generation/query checks cannot retire already accepted UIKit work. This matches A42's independently observed failure
  mechanism, but no live forwarding crash is claimed.
  Unlike A42's queued Combine publications, Forward assigns topics and starts apply synchronously on MainActor; the precise
  deferred UIKit callback schedule remains unverified. Separately, a failed query reset retains the previous query's topics;
  a cursor-zero `load(reset:false)` retry then merges old and new query results. The accepted-query boundary is part of this repair.
- Repair boundary: forwarding topic selector only. Reuse `ForumTopicsSnapshotState` for transaction-owned models/clients,
  keep outgoing models through exact completion, and coalesce only the next payload. Preserve raw TDLib cursor, rights checks,
  selected topic identities and final forwarding service revalidation. Selection must wait for a settled/current displayed row;
  fallback must return the exact dequeued cell. Do not combine A46b pin ranking or unrelated forwarding UX in this slice.
- Proof plan: native production-controller/table probe with held apply completion, rapid accepted page/query changes, retained
  reconfigure IDs, stale completion, selection gates and teardown; existing forum snapshot/active-search regressions.
  Use injected read-only endpoints, no real forwarding/server writes. Telegram's separate UI infrastructure is not imported;
  this is UIKit transaction correctness under the established A42 contract, not a new server ordering claim.
- Initial integration `86bf0e9` (worker `7710a9`, reviewed tree `eb2c373e`) serializes page/toggle snapshots, keeps outgoing
  models/clients, gates query selection and replaces previous-query rows on cursor-zero retry. Primary build
  `build-Debug-20261003-112447-8466-30715.log`: PASS9s, complete log zero warnings/errors. Native PID14762 at11:27:30+04
  FAILED its teardown assertion; this was not a runtime-complete handoff.
- Diagnostic-only `ff423d0` (worker `6969df3`, reviewed tree `12cea598`) adds exact pop/containment receipts without changing
  production guards. Build `build-Debug-20261003-113410-35144-20625.log`: PASS9s, complete log zero warnings/errors.
  Native PID35915 at11:34:59 passes transaction/query/fallback/selection cases and post-retirement cleanup. Immediate pop receipt
  is parent=nil, absent from stack, retired=false, with models1/2 retained and apply busy; the later receipt is retired=true and empty.
  Thus waiting for `didMove(nil)` fixes the probe's timing assumption but does not establish immediate detached-owner admission.
  Next bounded correction must reject late reads/actions/new applies during this actual detached interval, while retaining models
  through the exact native completion and avoiding permanent retirement in a cancellable `willMove(nil)` transition.
- Follow-up `db7e6bf` (worker `5a4ac6`, reviewed tree `e29ea3c`) remembers first non-nil containment. After that receipt,
  actual parent/children detachment rejects page/action/enqueue/drain admission before the terminal lifecycle callback; bootstrap
  reads stay compatible and exact completion remains unconditional. No window/nav-stack/`isMovingFromParent` gate or irreversible
  `willMove(nil)` retirement is introduced. A retained parent can continue its current read.
  Single SwiftFormat0/2; build `build-Debug-20261003-114744-67424-30857.log`: PASS9s, full log zero warnings/errors.
- Native PID68845 on audit59EB535C/iOS26.5, report11:48:19+04: PASS actual production controller/table, held native completion,
  coalesced queries, same-cell/fallback, closed/selected rows, failed head→retry/raw append cursor, stale source/query and teardown.
  Immediate pop receipt is retired=false/owner=false/parent=nil. The native read returns distinct cursor(91,44,900) and its exact
  Task.value plus held completion are consumed **before** retirement wait; original cursor and starts2/2 remain unchanged, queued
  and late models are not admitted. The intermediate receipt is still retired=false; final lifecycle cleanup empties models.
  First attachment is separately awaited; synthetic retained-parent `willMove(nil)` keeps loading/selection alive. This does not
  prove an actual canceled swipe, whole modal dismissal, live rights resolution or real forwarding. No server delivery is exercised.
- Existing supplementary regressions pass on the integrated follow-up: PID75259 restoration/snapshot11:50:49/52+04,
  PID75908 active-search11:51:32. Reports are fresh from newly resolved containers. Evidence under
  `.build/ui-probe-evidence/astra-a48-forward-snapshot/`; natural UIKit overlap and actual Forward delivery remain unverified.
