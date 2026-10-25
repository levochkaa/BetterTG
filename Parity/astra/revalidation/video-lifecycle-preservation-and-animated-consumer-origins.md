# Video lifecycle preservation and animated consumer origins — 2026-10-02

- A15b1 `2fac04c` (worker `2b45d35`): background/camera/audio interruptions join the immutable capture finalizer, stop input and
  preserve the canonical recording. A per-capture background lease ends once; expiration cancels only a matching unadopted writer,
  never an accepted store save. Repeated events cannot renew the lease. Foreground restores only the retained route/generation to
  paused preview; it cannot restart capture/playback or revive a navigation-detached owner. Initial background state is respected.
- Review caught `.sending` being set before asynchronous export. The fix checks lifecycle epoch immediately before `onSubmit`,
  removes only its own export/thumbnail and retains the recording; an already invoked `onSubmit` is not canceled. Explicit Cancel
  remains destructive. References are the pinned current/pre ChatController→stopMediaRecorder→preview paths in A15a above.
- Four Swift files formatted together; integrated build `.build/logs/xcodebuild/build-Debug-20261002-182819-4794-15394.log` passes
  without warnings (10s). Exact product `2fac04c`: PID `6152` lifecycle probe passes 11 recorder/native-writer/private-store scenarios,
  pending preparation, background→foreground during real export, accepted suspended submit, immediate expiry and canonical cleanup.
  Separate launches pass A15a navigation (`7592`), A17 native finish (`19855`), A16 submit ownership (`23359`). Evidence:
  `.build/ui-probe-evidence/astra-a15b1-primary`; worker source/build notes in `astra-a15b1-worker`.
  Lifecycle inputs/background backend are injected; no user stores/sends, hardware capture, real OS suspension/expiration,
  audio-notification delivery or process-death recovery were tested. Voice background/intent ownership remains A15b2.
- A05b `7e02e60` requires an explicit originating client in AnimatedFileView, custom emoji, timeline text/reactions/dice,
  composer stickers, topic icons and gallery cells. The dynamic repository overload is removed. Gallery's existing video owner
  remains usable without reconstructing a client; a new animation cannot fall back to global `td`. Reuse clears thumbnail pixels.
  Fifteen Swift files formatted together; build `.build/logs/xcodebuild/build-Debug-20261002-183343-25876-8180.log` passes without
  warnings (15s). PID `31000` passes animation-authority, native A07 and PiP-context regressions in `astra-a05b-primary`.
  Independent read-only A05a/A05b delta review found no new blocker. Actual multi-account animation/view-decode races, shared demand
  and nonanimated/static-image client plumbing remain outside this bounded proof.
