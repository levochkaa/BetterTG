# A37 focused prompt baseline — 2026-10-03

- `c37e10c` (worker `fc815ea`) adds only a DEBUG `-ui-probe-navigation-prompt` fixture: actual classic navigation and editor,
  temporary isolated key window restored on exit, real first responder/selection, delayed public geometry and retained-stack
  replacement. No production layout changes. One-file format; `build-Debug-20261003-000305-73770-24276.log`: PASS16s,
  zero warnings.
- PID `79838`: baseline three samples bar/safe/field116/116/136. Waiting sample116/150/170 fails the fixture's strict bar=safe
  assertion, but does not show field overlap. Public prompt/safe-area APIs do not guarantee that equality. This failed probe
  is not proof of the original clipping cause. Correct the fixture to collect all phases and separately test harmful overlap,
  baseline return and focus/selection without forced layout. Private report `.build/ui-probe-evidence/astra-a37-primary`.
- `9a07f1a` (worker `512fb29`) corrects only that measurement contract: public bar/safe difference is diagnostic;
  harmful field/bar overlap, exact selection, focus/text and final ready-baseline remain failures. All 24 samples/8 phases
  are collected before verdict. One-file format; `build-Debug-20261003-001518-2098-7636.log`: PASS9s, zero warnings.
  PID `4253` passes all phases including fresh client and exact retained-stack replacement: no harmful overlap, focus/text/
  selection loss or final-baseline failure; nine waiting samples have bar116/safe150/field170. No forced layout or production
  invalidation added. Private proof `.build/ui-probe-evidence/astra-a37-complete-primary`. Original actual clipping remains
  open/intermittent; this isolated baseline does not establish its cause or prove real foreground/painted-pixel behavior.
- Actual delayed diagnostic at `aad1ac9`, PID `32182`, with `-ui-diagnose-profile-editor-layout`: focus first own-profile
  field without editing, Home00:39:11→foreground00:39:45. Immediate samples show bar150/safe116/field136, but all three
  delayed settled samples return116/116/136 with first responder retained. Settled screenshot is clean; Back exits without
  Save or an agent-authored draft. `.build/ui-probe-evidence/astra-a37-delayed-primary` contains the bounded geometry JSON
  and pixels. This confirms transient geometry in this run, not the cause or repair of the earlier persistent clipping.
