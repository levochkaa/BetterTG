# A41 static artifact cleanup dependency order — 2026-10-03

- Two consecutive builds `015206-28264-17404` and `015425-28980-13074` fail when cleanup deletes TDLibFramework.framework during
  Xcode's automatic lipo/copy/sign. Failed manifest `5bf934207b9f9cd20ed3f407db54958a` shows the cleanup waits only for the
  explicit copy-files phase, while SwiftPM's package copy and child signing are independent producers. No dependency or cache
  reset is warranted.
- `f7d7090` adds only two XcodeGen `inputFiles`: the embedded static bundle and its `_CodeSignature`. The generated graph
  now orders copy → child signing → cleanup → unsigned-product-ready → app signing without a cycle. Cleanup still removes only
  the redundant generated static artifact, recoverable by the next build; package sources/cache and TDLibKitDynamic remain intact.
- Integrated source includes A39 follow-up `a8b0988` (worker `94016cd`); all four outstanding Swift files formatted together0/4.
  `build-Debug-20261003-015646-29545-22064.log`: PASS7s; `--no-code-signing` log `015734-29820-5419`: PASS4s;
  final signed `015810-30055-29778`: PASS5s. Complete logs have zero warnings/errors; main-app metadata extraction still runs,
  extension extraction does not. Final redundant bundle is absent and `codesign --verify --deep --strict` passes.
  Independent graph/source review and shell warning fixtures pass. Device/archive signing remains unverified.
