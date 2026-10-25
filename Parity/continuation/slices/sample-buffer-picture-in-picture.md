# Sample-buffer Picture in Picture slice

- **P0 flow:** FFmpeg WebM VOD PiP using the pre-Liquid/current `NativePictureInPictureContentImpl` AVKit contract while retaining
  BetterTG's existing UIKit owner, Combine state, TDLib range session and restore coordinator.
- Implemented: exact layer-keyed `ContentSource`; strongly retained lock-backed playback adapter; finite current-containing range;
  playing/buffering/paused mapping; explicit setPlaying; signed skip with past-end reset; render-size forwarding; background audio allowed;
  pause/duration invalidation; native/sample source reconciliation; start/stop timeouts; pending-start strong retention; deletion/restore/audio
  lifecycle; deferred failed-player teardown; forced-timeout controller retirement and exact stale-controller rejection.
- Verification: the production gallery-owner fixture exercises the real content-source factory despite system PiP being unsupported and
  proves sample layer/delegate identity, transport/range behavior, exact-once completion, source continuity, zero extra TDLib cancellation,
  deferred stop-before-close, native fallback route, pending-start barrier and stale timeout callback rejection. Actual system-window PiP
  and background restore still require a capable physical device.
