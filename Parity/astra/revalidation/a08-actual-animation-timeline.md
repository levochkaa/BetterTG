# A08 actual animation timeline — 2026-10-02

- `6a03761` (worker `25c412d`) replaces nominal capped FPS/count with native decoded PTS and actual EOF. Binary search selects
  frames; missing/backward/duplicate timestamps fall back to the previous decoded end. The last decoded duration determines loop
  end. Native non-EOF read errors no longer count as EOF. Existing pixel-read missing-PTS zero behavior is preserved.
- Timing-only scan is coalesced by full path/inode/size/mtime through weak ownership, runs off-main, checks cancellation around
  native reads, and publishes only a complete index. Bounds: 65,536 frames / 512KiB charged to existing asset cache, 10s between
  native calls. One native call cannot be interrupted by that deadline. Last-waiter cancellation serializes native teardown and
  restart; primary review added cancellation recheck at continuation registration and a deterministic regression for that race.
  Failed/over-budget scans retain the first-frame fallback; pixel cache limits are unchanged. Device energy/latency remain unmeasured.
- References: pinned current/pre `MediaPlayer/Sources/SoftwareVideoSource.swift` 213–227 and
  `AnimatedStickerNode/Sources/VideoStickerFrameSource.swift` 343–351,409–420. This does not claim Telegram renders at uncapped
  nominal 60FPS. TDLib animated-file demand/API is unchanged. Native EOF is not universal truncated-container integrity proof.
- Primary 14-file integration SwiftFormat, build `.build/logs/xcodebuild/build-Debug-20261002-193037-75193-27184.log`: PASS16s,
  zero warnings. Audit Simulator source `f2bbe89`, PID `75703`: `-media-probe-animation-timing` passes real pinned-iOS decode
  of VFR4-frame GIF, 120-frame60FPS and 660-frame22s WebM, nonzero origin, one frame and zero/under/over metadata duration;
  actual last/first pixel frames, EOF wrap, bounded-index fallback, shared cancellation/restart and pre-registration cancellation.
  A06 demand/authority pass. Separate launch source `f87ad74`, PID `78753`: A07 worker create/read/reset/destroy/reuse probe passes.
- Proof: `.build/ui-probe-evidence/astra-a08-primary`; worker host-native FFmpeg9.0.2 evidence remains separately labelled in
  `astra-a08-worker`. No real sticker feed/TDLib download/UI playback/performance claim; no user stores or server writes.
