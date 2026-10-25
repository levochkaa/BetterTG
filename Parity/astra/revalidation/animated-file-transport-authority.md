# Animated file transport authority — 2026-10-02

- A05a `b0ed754`: all three TGS/WebP/FFmpeg views use one configured request with captured account/client/file identity.
  Scoped notifications check the accepted origin at main delivery; download/cancel closures retain the original client.
  Client replacement retires the request and view. Asset/frame callbacks check request identity, current source and path;
  canceled same-file reuse cannot install an old decode. Thumbnails use the existing explicit-account/client loader.
  Complete files issue no teardown cancellation. Native worker ownership, alpha, caches and timing remain unchanged.
- This is deliberately partial: callers still capture the active client at configure. An old asynchronous consumer can pass an old
  File into a new configure; the next slice makes originating clients explicit through custom emoji, timeline, picker and gallery.
  Shared visible/prefetch download demand (A06) is not implemented by this request wrapper.
- Reference: pinned pre-Liquid `AnimatedStickerNode/Sources/AnimatedStickerNode.swift:288–291,348–424` owns its source subscription,
  disposes/replaces it and gates playback by visibility. TDLib pinned `downloadFile` documents immediate non-synchronous state plus
  `updateFile`; `cancelDownloadFile(onlyIfPending:true)` only cancels a pending request. No Telegram infrastructure imported.
- Six Swift files formatted together. Final build `.build/logs/xcodebuild/build-Debug-20261002-182359-89980-13950.log` passes without
  warnings (11s), after correcting unused-result and weak-reference diagnostics. Simulator PID `91050`, built from this exact source,
  passes `-media-probe-animation-authority`: isolated actual request/notification path, colliding/foreign/unscoped/wrong-file updates,
  queued account replacement, same-file reuse, late RPC, captured cancel and deinit cleanup. Backend closures are fixtures; no TD calls.
  A07 native worker regression and A23 Chat/Root probes also pass in `.build/ui-probe-evidence/astra-a05a-primary`.
  This does not prove real sticker playback, account switching, or all consumer origins.
