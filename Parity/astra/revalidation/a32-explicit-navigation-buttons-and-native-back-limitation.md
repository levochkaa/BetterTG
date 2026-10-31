# A32 explicit navigation buttons and native Back limitation — 2026-10-02

- `a20ec2f` (worker `71289be`) uses an app-owned UINavigationBar with ordinary UINavigationControllers at all seven production
  constructors. Per-instance `hidesSharedBackground` is reapplied to initial/late/replaced buttons and the previous item's native
  back item. Targets/actions/menu/customView/enabled/delegate remain unchanged. Native Back is not replaced with a custom left action.
  Existing full-width material appearance gains compact-scroll-edge coverage; no search/safe-area/gesture layout changes.
- References: pinned pre-Liquid `Display/Source/NavigationBar.swift`1153–1167,1194–1227,1286–1310 and
  `NavigationButtonNode.swift`299–313; public UIKit26.5 `UIBarButtonItem.h`147–166, `UINavigationItem.h`31–38,154–165.
  The background flag is not an appearance-proxy property. No Telegram infrastructure/private subview traversal copied.
- Nine Swift files formatted together; `build-Debug-20261002-220321-68144-21386.log`: PASS16s, zero warnings. PID `76056`:
  actual offscreen navigation/bar probe, generic client and forum restoration regressions pass. Probe verifies item identity,
  initial/late/replaced actions, generated/explicit back, native stack methods and all four appearance states, not visible chrome.
- Production Saved → Profile → Edit, same PID: Save is plain text without its capsule; Back remains circular on Profile and a
  capsule on Edit. Back returns to Profile and Saved without saving. idb exposes editor navigation as one Group, not separate
  Back/Save children; coordinates came from screenshots. Long-press returned to Profile; native history-menu behavior is unverified.
- Diagnostic-only `38c912a` (worker `80ad6e8`) records bounded public item flags without titles/IDs/content. Two-file build
  `build-Debug-20261002-221009-76792-23655.log`: PASS19s, zero warnings. PID `88393`: real attached owned bar, exact previous
  stack item, `hidesSharedBackground=true`, group0/plain/no custom action before and after layout, but the native Back background remains.
  This excludes an unconfigured bar/wrong-item explanation; it does not establish a UIKit implementation cause.
- One-line timing trial `99a6f0a` (worker `eda9c64`) sets the generated back flag before assignment. One-file format/build
  `build-Debug-20261002-221603-96136-10079.log`: PASS8s, zero warnings. PID `96492`: headless probe passes; actual Profile/Edit
  still show the same Back background. The ineffective trial is removed; no private workaround or custom pop action is introduced.
- Cleanup `23141df` (worker `7d361e1`) removes synthetic back items and title tracking. UIKit retains nil Back and adaptive
  title policy; only explicit back/left/right buttons receive the background flag. Two-file format and integration build
  `build-Debug-20261002-223232-18887-16383.log`: PASS43s, zero warnings. PID `20378`, source `23141df`, same audit Simulator:
  actual navigation probe passes nil preservation through title/display-mode/stack changes and explicit→nil reset.
  Saved → Profile → Edit → Back → Saved succeeds without edits. Save remains plain; native Back remains circular on both
  Profile and Edit. Public diagnostics confirm attached owned bars, nil back items and exact previous stack ownership.
  Editor navigation remains one AX Group; Back coordinates came from settled pixels. This cleanup is not a visual Back fix.
- Private captures/diagnostics: `.build/ui-probe-evidence/astra-a32-primary`. No profile fields edited/Save tapped/server mutation.
  Native Back/background/history, interactive cancel, first-frame polish, RTL/dynamic widths/dark mode and native search remain open.
  Continue independent P1 list ordering while preserving this reproducible public-API limitation.
