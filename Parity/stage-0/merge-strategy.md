# Merge strategy

1. M1 `897829a`: `codex/parity` from main ← parity-continuation (base `1476556`, five conflicting files), plus
   TDLib 1.8.68 adaptation of parity code. Xcode 27 build, 0 warnings.
2. M2 `dd4528d`: `codex/parity-astra-tdlib2` from a21e ← `ee8cf99` (base `5e6f5a0`). Astra is ported to TDLibKit
   2.0.0 and `Packages/TDLibKitDynamic` is removed. Xcode 26.6 build, 0 warnings. Merging `ee8cf99` rather than main
   leaves the final merge a single base.
3. M3 `ea64c34`: `codex/parity` ← `codex/parity-astra-tdlib2` (single base `ee8cf99`). Conflicts are astra
   against parity-continuation and main's October work; the result is adapted to TDLib 1.8.68 and Xcode 27. A full
   recompile of 334 Swift files has 0 warnings.
4. `9a7cccc`: fix found by the Stage 0 smoke (F1).

All three histories are reachable from `codex/parity`. `main` and both source branches are unchanged.
