# Merge strategy

1. M1 `9d10e35`: `codex/parity` from main ← parity-continuation (base `6dd705c`, five conflicting files), plus
   TDLib 1.8.68 adaptation of parity code. Xcode 27 build, 0 warnings.
2. M2 `6716537`: `codex/parity-astra-tdlib2` from a21e ← `0b8fc67` (base `e88036e`). Astra is ported to TDLibKit
   2.0.0 and `Packages/TDLibKitDynamic` is removed. Xcode 26.6 build, 0 warnings. Merging `0b8fc67` rather than main
   leaves the final merge a single base.
3. M3 `92f6bf1`: `codex/parity` ← `codex/parity-astra-tdlib2` (single base `0b8fc67`). Conflicts are astra
   against parity-continuation and main's October work; the result is adapted to TDLib 1.8.68 and Xcode 27. A full
   recompile of 334 Swift files has 0 warnings.
4. `2d54dc3`: fix found by the Stage 0 smoke (F1).

All three histories are reachable from `codex/parity`. `main` and both source branches are unchanged.
