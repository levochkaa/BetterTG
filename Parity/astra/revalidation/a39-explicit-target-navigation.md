# A39 explicit target navigation — 2026-10-03

- `054d8e0` (worker `7f2d9d9`) retires retained viewport intent when accepting explicit navigation, consults the current
  snapshot marker, and holds target/quote until snapshot, layout, window and source are valid. Pending navigation fences
  initial/latest compensation; gestures, supersession, source revocation and failed admission retain their cancellation rules.
  Initial positioning is synchronous; navigation in an initialized Chat remains animated. Existing ChatVM history logic is
  unchanged apart from opt-in content-free phase diagnostics. Three-file format; integration
  `build-Debug-20261003-005409-91096-31077.log`: PASS31s, zero warnings.
- Independent review found a final-release wakeup missing from rotation and a loaded fast-path bypass. `511c13a` (worker
  `65341a6`) pairs all nine layout owners through one release helper and retries pending navigation after the last external
  release. Explicit scroll's own release does not recurse into unavailable layout. Delta review is clean; three-file format,
  `build-Debug-20261003-005819-95305-8829.log`: PASS9s, zero warnings.
- Source `511c13a`, audit Simulator PID `95662`: viewport-authority and complete profile-restoration/A38 probes pass.
  Navigation fixtures use the actual ticket/viewport/release helpers and real UICollectionView/diffable layout, but a
  value-only consumer, not full ChatView/ChatVM or system rotation. They do not test the production animated-scroll/highlight
  sequence. Reports: `.build/ui-probe-evidence/astra-a39-primary`.
- Cold control at `6723b65`, PID `39878`, without Home/client rollover already failed to reach the same old Files target
  after about70s (`astra-a38-settled-primary/cold-target-settled.png`). The observed failure is not specific to restoration.
  At `511c13a`, PID `95662`, fresh Saved → Profile → Files → older June document at01:03:16 also returns to latest September/
  October messages. Phase reads `applied`, target AX is absent, and settled screenshot confirms the miss. Repeating the same
  already-loaded target at01:05:51 moves only to early September, still without the target. No file opened/downloaded and no
  message/profile/folder saved. Private screenshots and phase remain under the A39 evidence directory.
- `db29e06` (worker `49fd34a`) adds opt-in numeric geometry to actual ChatView and renames the misleading pre-command phase
  to `offset-command`. At most64 samples, reserved settled checks, lazy metric capture, weak exact-request delayed callbacks,
  serial background JSON writes; no IDs/content exported and no scrolling policy changed. Both-file format and independent
  immutable review pass. Integration `build-Debug-20261003-011303-7581-26376.log`: PASS10s, zero warnings.
- Actual source `db29e06`, PID `8251`, only `-ui-probe-message-navigation`, cold Files target tap01:14:45: window is ready67ms,
  explicit animated command70ms requests5627.833 from-94.333. Two highlight snapshots finish before motion continues through
  -51,78.333,289. Automatic capture at115ms sees pending0; automatic restore153ms calls anchor writer154ms, synchronously emits
  animation-end and rewrites offset to78.333. At10.571s, current target5743.833 remains offscreen, correct mapping/source/window
  flags all hold. This proves mid-flight automatic compensation interrupts explicit navigation; immediate highlight cancellation
  is rejected for this run. Which automatic capture caller (self-size versus reconfigure) is not distinguished, and animation-end
  alone is not successful arrival. Native helper did not exercise this production sequence.
  Trace, failed settled screenshot and AX check: `.build/ui-probe-evidence/astra-a39-geometry`; no send/edit/delete/export or
  file open was invoked. Normal read-state side effects of chat navigation are not excluded.
  Last persisted settled sample is10s; the scheduled25s sample is absent, so do not claim25s diagnostic coverage.
- Diagnostic-proof documentation build `build-Debug-20261003-011704-11526-27558.log`: PASS6s, zero warnings.
- Repair boundary: hold explicit navigation authority until measured target settlement; gate automatic and inset/anchor
  compensation during flight, remeasure estimated cell geometry, and retire authority on drag/new target/latest/source change.
  Preserve animations, quotes, current source and the existing history/revision contracts. No wholesale timeline or loader rewrite.
- `0b900ad` (worker `b8caad3`) adds the production native-scroll settlement driver and gates compensation until fresh raw
  membership, current source, mounted visible cell and two stable geometry observations agree. Drag/latest/cover/source/new-target
  cancellation retires it; quotes/highlight start only on success. Independent immutable review passes. Four-file format0/4.
  Integration `build-Debug-20261003-014324-25949-6943.log` succeeds13s but has one metadata warning; it is not warning-free (A40).
- Audit Simulator after user app restart: same audit UDID/runtime, authentication preserved, source `0b900ad`, PID `26494`.
  Native viewport-authority probe passes actual production driver/native animation/estimated UICollectionView plus cancellation,
  remap, supersession, deferred layout and failure deadline. Full ChatView wiring is checked by the separate real flow below.
  idb hierarchy/input works; screenshot backend fails, so `simctl io screenshot` supplies pixels without activation or data reset.
- Actual cold Saved → Profile → Files → old June target at01:46:27 now reaches the message, but phase is `scroll-failed`.
  Native command50ms→5627.833; native end360ms; corrections404ms→7031.5 and504ms→6854.5. Subsequent UIKit geometry leaves
  offset6900.333 versus target6854.167 (46.167pt error); target AX/cell are visible through25.152s. No automatic anchor writer
  interrupts flight. The two-correction limit fails before highlight; cold settlement remains open, not counted as complete.
- Repeating the already-loaded target at01:49:10 passes `scroll-settled`333ms; target mounted/visible, offset6953 versus
  desired6953.167, stable10.501s. AX target y387.667/height118 and settled screenshot agree. Evidence:
  `.build/ui-probe-evidence/astra-a39-settlement/{cold,loaded}`. No send/edit/delete/export/file open; ordinary read-state effects
  are possible. Next repair is progress-bounded convergence under the existing deadline, not a relaxed visibility-only success test.
- `a8b0988` (worker `94016cd`) permits at most8 final corrections, requires measured residual improvement with only one stalled
  pass, and retains the2s failure-only deadline. Nonanimated UIKit offset changes keep geometry checking alive. Exact0.75pt,
  mounted/visible cell and two-frame stability remain mandatory; there is no visibility-only success. Independent review passes.
  Native probe adds successive real estimated neighboring cells plus explicitly injected residuals; stall/oscillation limits pass.
- Final audit Simulator source `f7d7090` (includes `a8b0988`), PID `30616`: expanded viewport-authority probe passes. Actual cold
  target tap02:02:22 settles572ms after three corrections, offset6808 versus target6808.167. Target AX y387.667/height118 and
  settled screenshot agree; error-0.167pt remains stable25.297s.
- Same PID: scrolled Files target y188.667/height52.667 before Home02:05:03. Lifecycle logs confirm ownership released02:05:05.027,
  restored02:06:01.959, profile replacement accepted02:06:02.647. Files keeps the same row geometry. Open in Chat02:06:57 settles
  224ms on the fresh client, offset5450.667 versus5450.5, mounted target AX y388/height118, stable25.152s. Repeating the loaded
  target02:11:15 settles38ms with the same0.167pt error and geometry, stable25.151s.
  Proof: `.build/ui-probe-evidence/astra-a39-convergence/{cold,foreground,loaded}` plus fresh native report. No sends, file opens,
  deletes, exports or account resets; ordinary read-state effects remain possible. This closes the measured target defect, not
  exhaustive quote/album/rotation/gesture parity. A40/A41 below provide final warning-free integration builds.
- Documentation checkpoint `build-Debug-20261003-021404-33516-4379.log`: PASS5s, complete log zero warnings/errors; prohibited
  production/dependency marker scan empty, AGENTS/CLAUDE identical. Simulator remains booted and was never activated separately.
- References: pinned current/pre `ChatControllerNavigateToMessage.swift`342–422,474–507/333–360 distinguishes loaded target
  navigation from cancellable 50-message initial search and target/missing completion. Pinned TDLibKit `getChatHistory`,
  `getMessage`, captured ChatLocation and current history revision admission remain unchanged. No Telegram infrastructure copied.
- Follow-up diagnostic `b346b9f` (worker `c662025`, reviewed tree `265e323d`) adds an opt-in192-event DEBUG value trace,
  terminal deadline/budget reasons, geometry before consumer target clear and separate post-result outcome/visibility/quote.
  No extra driver resolve/layout calls;2s watchdog,3s probe wait,0.75pt threshold, correction budget and predicates unchanged.
  Worker format/build `155938-6424-25004` PASS14s/fullzero; primary joint format0/2/build `160215-12692-11186`
  PASS11s/full1486-line log zero warnings/errors. Current reference `6ad963e5` and pre `8e7e5fe`,
  `submodules/TelegramUI/Sources/Chat/ChatControllerNavigateToMessage.swift`342–380/333–365 rechecked read-only.
- Audit59EB535C/iOS26.5 standalone run1 PID15417/container `BABBC350-720B-4207-8832-1DDA59F3166D`, report16:03:20 PASS;
  run2 PID18301/container `D3CFE2EE-CACA-4105-B7D5-13427693DC49`, report16:04:15 PASS. Run3 PID22802/container
  `BB7C17B1-AF0D-43A6-B547-E42A60414EE4`, report16:06:29 FAIL on unchanged source/product. Full content-free receipts are
  preserved under `.build/ui-probe-evidence/astra-a39-diagnostics/{first,second,third-failure}.txt`; no UI gesture or server mutation.
- Run3 identifies a deadline failure, not correction-budget rejection or a post-result-only oracle failure: commands `[true]`,
  no corrections, target not intersecting/mounted/visible both before clear and after completion, residual304.5pt. Native ends
  arrive0.342s and1.299s. First verifier observation0.591s sees offset4626.6667/target4258.5; second2.151s sees4563/4258.5,
  stops checking and clears receivedEnd. Deadline fires2.156s. The second accepted end retained the old first observation.
  End-reset is observed, but that frame was already after the2s budget: this does not prove it caused the timeout.
- Timing follow-up `a5d721d` (worker `a7fd0db`, exact peer-reviewed tree `b1abbf3a`) adds callback entry/display-link timestamps,
  timing around existing resolve calls and bounded aggregates from existing10ms wait resumptions. No extra timer, task,
  resolver/layout call, deadline extension or predicate change. Joint format0/2; primary build `161829-36511-3066` PASS11s,
  full1482-line log zero warnings/errors; worker `161246-31131-24056` PASS9s/fullzero.
- Same Audit Simulator timing run1 PID37004/container `7CAE36F2-8631-458B-A80C-59907020F3CE`, report16:19:13 PASS;
  run2 PID38384/container `261CC0A4-26C1-45F0-B685-AC69CF6AE3DF`, report16:20:15 FAIL. Native end0.343s; callback entries
  1.2465/2.2683s with display timestamps0.5304/1.3458s: delivery delays0.716/0.922s. Callback durations0.118/0.295ms,
  resolver spans0.054/0.027ms. Completion wait has20 resumptions/maxGap0.670s, including378/430/670/347ms gaps.
  This establishes main-actor/run-loop scheduling delay in this run, not continuous thread blocking or its source.
- Run2 reaches a mounted/visible target with0.167pt residual after correction at2.268s, but deadline2.316s precedes the next
  two-frame recheck. Commands `[true,false]`; no end-reset or correction rejection. Thus earlier end-reset is not necessary
  for this intermittent deadline. Full content-free reports: `.build/ui-probe-evidence/astra-a39-diagnostics/timing-{first,second}.txt`.
  No actual ChatView navigation or server mutation is exercised by this isolated native fixture; no production timeout fix claimed.
- Next bounded counterexample: hold only verifier delivery, accept genuine native end1 and one sample, inject a separately
  labeled native offset animation, then accept genuine end2 before the next sample. Establish whether retained pre-end2
  geometry loses the current checker. Keep natural animation/cancellation checks; a repair must retain stale-end protection,
  exact visible/centered settlement, correction budget and deadline. This is separate from scheduling-delay diagnosis above.
- Timing checkpoint build `162308-41757-22286` PASS8s; complete1385-line log zero warnings/errors. Production/dependency
  prohibited-marker scan empty; AGENTS/CLAUDE identical; only this checkpoint document remained uncommitted before recording.
- Controlled latest-end baseline `245e7b8` (worker `c7eaa76`, exact reviewed tree `ea732dcf`) adds a dedicated
  `-ui-probe-navigation-end-order` fixture. DEBUG manual verifier delivery retains the actual display link and admits calls
  only while the production checker/current command exists. Native delegates are forwarded; no receivedEnd/sample setters.
  Its accurate48pt estimates isolate ordering; the existing natural fixture retains80pt estimates and automatic frames.
  Joint format0/3; primary build `163140-63493-4382` PASS19s/full1486-line log zero warnings/errors; worker
  `162945-60442-7840` PASS8s/full1450-line log zero warnings/errors. Separate setup/deadline INCONCLUSIVE and contract FAIL.
- Audit baseline PID64657/container `321FBD05-6B75-4D61-AF06-D916B2846B1D`, report16:32:27: definite FAIL at0.8111s,
  before2s. Genuine end1 arrives0.4351s; first manual sample0.4444s records1696pt. A deliberately injected second native
  animation reaches1760pt; genuine end2 arrives0.7736s. Next manual observation resets receivedEnd and stops the checker,
  while ownership/target remain, commands `[true]`, no result or quote, residual64pt. The hook refuses a further frame after
  checker retirement. Six automatic callbacks were held. Full report: `astra-a39-diagnostics/end-order-baseline.txt` under
  `.build/ui-probe-evidence`. This is a controlled driver liveness counterexample, not actual ChatView relocation proof.
- Bounded repair plan: every accepted end invalidates both previous geometry samples while preserving the existing display
  link. Require two post-latest-end stable observations before correction/settlement; retain motion/stale-end rejection,
  visibility/centering, request/command identity, cancellation, correction cap and2s deadline. No loader/timeline rewrite.
  The independently measured scheduling-delay timeout remains open and is not explained or repaired by this change.
- `91baad4` (worker `d2770fa`, reviewed tree `548cf025`) implements exactly those two sample resets plus a comment.
  Accepted-end guard, current link/command, resolver calls and all failure/success predicates are unchanged. Reentrant end
  during resolve invalidates samples before the verifier reads them; movement between new samples still drops stale-end
  authority. Joint format0/3; primary build `163554-69774-7770` PASS8s/full1450-line log zero warnings/errors; worker
  `163342-66161-9874` PASS32s/full1450-line log zero warnings/errors. Exact-tree independent review PASS.
- Same Audit Simulator fixed controlled run PID70456/container `789ECA0E-CC76-4F42-86A2-C043AA4C26C2`, report16:36:36 PASS.
  The contract now requires two post-latest-end observations before one nonanimated correction; this dedicated scenario
  does not claim complete settlement, real ChatView relocation or the cause of earlier spontaneous timeouts.
- Ordinary automatic-frame viewport regression on the same source/product PID70970/container
  `1016F44C-2C52-4952-B2A4-7D1C9E79362C`, report16:37:19 PASS: native animated resize/quote, album remap, new-target/stale end,
  drag/latest/source/cover/missing-member cancellation, tracking-only retirement, deferred layout, failure deadline and
  successive self-size correction bounds. Consumer remains value-only; actual ChatView/TDLib/hardware gestures are not proved.
  Full reports: `.build/ui-probe-evidence/astra-a39-diagnostics/end-order-{fixed,natural}.txt`. No fixture RPCs or account-store
  mutations; Simulator remains booted and host focus was not activated.
- Final latest-end checkpoint build `163857-71725-11058` PASS5s, full1385-line log zero warnings/errors. AGENTS/CLAUDE
  identical; prohibited production/dependency markers absent; implementation commits and this focused proof record preserve
  unrelated files. Next: one bounded native startup profile to attribute scheduling delay, then queued ChatView mutations.
  Goal remains active; repeated-end actual ChatView behavior and spontaneous timeout root cause remain unverified.
- Documentation checkpoint `build-Debug-20261003-010725-3164-28383.log`: PASS5s, zero warnings. AGENTS/CLAUDE remain identical;
  prohibited production/dependency marker scan is empty. The reusable prompt also records background-only Simulator activation.
