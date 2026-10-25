# Isolated range and renderer-feedback proof — 2026-10-02

- Isolated iPhone 17 Pro / iOS 26.5 Simulator `BetterTG Astra Audit`, `59EB535C-3610-41A2-AB68-53A9467DC24B`,
  avoids B01 without modifying the original database. Each run used
  `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B -- ARGUMENT` and idb.
  Login screenshots/hierarchies and live processes accompany the probe output; no account login or server mutation occurred.
- A01/A02 recheck at `ad25f97`, argument `-media-probe-vod-ranges`, PID `78859`: all existing range checks plus
  `deadline-token/rearm=true` and `update-before-wait=true` passed. Evidence:
  `.build/ui-probe-evidence/astra-isolated-vod-range-probe/vod-range-probe.txt` and
  `astra-isolated-vod-login-visible{.png,-hierarchy.json}`. The process remained alive after 89 seconds.
- A03 preserves `pause()`'s unconditional `setRate(0, time: .invalid)`, including cancellation of pending rate changes.
  `snapshotPublisher` deduplicates the full Equatable snapshot, retaining changes to clock/rate, generation, topology, queues,
  errors and finish state. The bounded asynchronous feedback probe receives exactly one settled paused snapshot.
- One SwiftFormat invocation covered `FFmpegSampleBufferRenderer.swift`; warning-free build:
  `.build/logs/xcodebuild/build-Debug-20261002-142824-79043-26845.log`. Independent diff review found no blocker.
- `-media-probe-vod-sample-buffer`, PID `79850`: `pause-feedback-events=1`, 24 video/101 audio buffers, stable pause,
  seek generation/preroll, stale drops, finish delivery, rate 1.5 and zero renderer errors passed. Output:
  `.build/ui-probe-evidence/astra-isolated-vod-sample-buffer-probe/vod-sample-buffer-probe.txt`;
  login screenshot/hierarchy: `astra-isolated-sample-buffer-login{.png,-hierarchy.json}`.
- `-media-probe-vod-ffmpeg-controller`, PID `80246`: pause/rate/offscreen intent, last-seek-wins, persistent rolling windows
  (11 windows, one open, zero rollover seeks), EOF, offline/retry/clamp and cleanup passed; finite ranges, zero full downloads
  and zero renderer errors. Output: `.build/ui-probe-evidence/astra-isolated-vod-ffmpeg-controller-probe/vod-ffmpeg-controller-probe.txt`;
  login screenshot/hierarchy: `astra-isolated-ffmpeg-controller-login{.png,-hierarchy.json}`. Process alive after 51 seconds.
  Fixture SHA-256: `685af512ee52d20c4aa20ef182d7d208df242d45b674f8e6fc2bbef91bfeb810`.
- These are deterministic production-source probes, not live Telegram message playback or system PiP proof. The controller
  fixture's slightly unequal track ends do not cover A04's materially different durations. B01 remains unresolved.
  Both Simulators remain booted; the smoke agent disconnected its owned idb session.
