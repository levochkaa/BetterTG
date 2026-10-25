# VOD main-track and duration-authority proof — 2026-10-02

- A04 worker chain `23b1e49` → `61bb5e3` → `e87ef9c` was independently reviewed and integrated as
  `cf01515` → `5ef904f` → `e27d339`. C selects explicit video end before audio, clips the longer audio tail and preserves persistent
  windows/final video frames. Explicit duration travels to Swift separately from container estimates. At real EOF, observed frame
  ends resolve estimates in either direction; initialized seek cursors cannot invent media duration. Verified terminal summaries
  cancel both watchdogs. An unknown end with no observed main frame or explicit metadata fails safely, not with a fabricated EOF.
- Reference: pinned current/pre-Liquid `MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift` chooses `video ?? audio`
  (546/578 current, 547/579 pre-Liquid). No decoder, player-clock, queue/cache/lease architecture or dependency version was replaced.
- Native before/after evidence: `.build/ui-probe-evidence/astra-a04-native/` and `astra-a04-fallback/`, including harness, pinned
  fixtures, source snapshots and commands. Host FFmpeg 9.0.2 proves video 2s/audio 10.008s ends at 2s with all 20 video frames;
  missing-video-duration container estimates 8s/20s both resolve to 12s with all 144 frames, seek 11s begins at 11s, and seek 25s
  emits no frames but observes true EOF at 12s. Longer-video/shorter-audio, origin, standard and audio-only regressions passed.
  These host runs are not Apple media-clock proof.
- Worker final warning-free log: `.build/logs/xcodebuild/worker-A04-build-Debug-20261002-152136-73961-20174.log`.
  Primary one-call SwiftFormat covered four changed Swift files (`0/4` changed); warning-free `./build.sh build` at `e27d339`:
  `.build/logs/xcodebuild/build-Debug-20261002-153032-2363-12736.log` (18s).
- Authorized iPhone 17 Pro / iOS 26.5 Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, wrapper/idb only:
  PID `2903` with `-media-probe-vod-main-track -media-probe-vod-ffmpeg-decode` passed both. Main-track output is
  `.build/ui-probe-evidence/astra-integrated-vod-main-track/vod-main-track-probe.txt`; decoder output is
  `astra-integrated-vod-decoder/vod-ffmpeg-decode-probe.txt`. Explicit 2s EOF and known/initial seek 6→2s, both estimate variants,
  seek 25→12s, persistent sessions, cleanup and bounded queues passed. Decoder retained 24 VP9 frames/101 Opus buffers,
  95,641 stereo sample frames, monotonic PTS, 3 persistent pumps/one open/zero rollover seeks, sparse unequal-track handling,
  cancellation/supersession, SWR drain and close-waits.
- PID `3401` with `-media-probe-vod-ffmpeg-controller`: `.build/ui-probe-evidence/astra-integrated-vod-controller/`
  `vod-ffmpeg-controller-probe.txt` reports stable pause, rate 1.5, offscreen cancellation/intent, last-seek-wins, 10 persistent
  windows/one open/zero rollover seeks, EOF, offline/retry/clamp and zero renderer errors, plus every new main-track assertion.
  idb still sees the real Saved Messages row afterward. No sends, account switch, data reset or Simulator shutdown occurred.
- Proof limit from independent delta audit: mixed-metadata fixture is 84,225 bytes, below the 2 MiB range fetch. Auto-fulfillment plus
  `limit != 0` proves finite request shape, not playback before the complete small file is cached. Existing lookahead still treats
  fallback duration as authoritative; no controller blocker was proven because original decodeStart and actual accepted frames
  advance playback independently after the initial scan. Follow-up: reconcile lookahead duration authority and test >2 MiB media
  with unavailable/delayed tail ranges, seek beyond an estimate and explicit incomplete-byte-coverage assertions. Live Telegram
  streaming and active system PiP remain unverified; do not promote this bounded proof to global VOD parity.
