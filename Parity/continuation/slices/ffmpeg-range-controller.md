# FFmpeg range controller slice

- **P0 flow:** non-Apple WebM VOD controller, following pre-Liquid/current `ChunkMediaPlayerV2.swift` buffering/seek/EOF and
  `ChunkMediaPlayerDirectFetchSourceImpl.swift` packet-lookahead behavior through TDLib `downloadFile(offset:limit:)`,
  `getFileDownloadedPrefixSize`, `updateFile` and `cancelDownloadFile`.
- Implemented: MainActor Combine controller; serialized 2s normalized packet horizon followed by a bounded 60s
  decoder job; exact 1s source gate plus Apple raw sufficiency; play/pause/rate/seek/EOF; non-zero-origin and per-track intervals;
  typed offline/retry failures; last-target-wins generations; offscreen renderer/range suspension; sparse audio degrades to silence;
  source demand cancellation is operation-token/last-demand scoped.
- Verification: `./build.sh` and `./test.sh` pass with Xcode 26.6. The 11.208s DEBUG fixture launched through
  `RUN_ARGUMENTS="-media-probe-vod-ffmpeg-controller" ./run.sh` and reported deferred load, ≥1s initial gate, ≤60s window,
  autoplay, visible buffering, stable pause, 1.5× rate, offscreen suspension/cancellation, preserved intent, last-seek-wins,
  seek-first PTS, EOF/no-loop, offline/retry, seek clamp, zero renderer errors, finite range downloads, zero full downloads and cleanup.
  `git diff --check` is clean.
- Persistent session rollover is complete; sample-buffer PiP remains the independent VOD architecture gap.
