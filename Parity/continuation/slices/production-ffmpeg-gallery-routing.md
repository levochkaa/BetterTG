# Production FFmpeg gallery routing slice

- **P0 flow:** WebM/VP9 VOD in the existing UIKit inline/fullscreen owner, following pre-Liquid `UniversalVideoGalleryItem.swift`
  central visibility and `ChunkMediaPlayerV2.swift` backend continuity without importing Telegram infrastructure.
- Implemented: MIME+extension routing; public range streaming; secret/non-streaming full-download handoff; cached-file FFmpeg re-entry;
  one controller/view/lease across inline and fullscreen; mute/rate/seek/control routing; offscreen demand suspension with preserved intent;
  first-frame/thumbnail transition fallback; typed failures; generation guards for every native and FFmpeg Combine stream; stale lease
  invalidation; native MP4/MOV/M4V and AVPlayer PiP isolation.
- Verification: `./build.sh build` succeeds without warnings. The combined native+FFmpeg owner probe launched through
  `./build.sh run -- -media-probe-gallery-owner`; idb readback proves `ffmpeg-route=true`, `same-controller=true`,
  `offscreen-intent=true`, `finite-ranges=true`, `ffmpeg-invalidate=true`, native `same-item=true`, zero full downloads for streamable
  fixtures, exact return-to-inline continuity, terminal lease cancellation and no stale attachment callbacks.
