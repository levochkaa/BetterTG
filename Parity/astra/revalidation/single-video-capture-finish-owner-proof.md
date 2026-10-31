# Single video capture finish-owner proof — 2026-10-02

- A17 worker `6809716` integrated as `3ab7079`. Capture contexts carry immutable preparation generation and one manual/automatic
  finish owner through native completion and MainActor delivery. Duplicate/competing manual Stop returns nil; it cannot convert an
  automatic success into failure cleanup. Cancellation/replacement cleans only undelivered owned output; a delivered asset survives
  later capture cancellation. Missing callback cleans its own output. Recorder tasks clear only their operation token; accepted
  automatic finish fences late start/duration/stopping updates, including the preparing/Record More interval.
- Reference: pinned current/pre-Liquid `Camera/Sources/VideoRecorder.swift` 367–376 reserves stopped state before finishing and
  delivery; `LegacyInstantVideoController` guards completion/dismissal. A15 preservation and A16 consumed-preview ownership are unchanged.
- Five Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-165751-81511-11272.log` (23s). Worker final log copied with `worker-A17-` prefix;
  `.build/ui-probe-evidence/astra-a17-worker/README.md` records its scope.
- Audit Simulator, PID `1196`, `3ab7079`: `-media-probe-video-note-finish` passes actual capture-session finish/cancel methods with
  a real H.264/AAC writer. Suspended native-finish and delivery windows cover competing/duplicate Stop, cancellation, replacement,
  missing callback, exactly-once error and retained transferred output. Actual recorder operation helpers cover stale cleanup and
  late preparing/start/duration/stopping. Result and seven A30a/A27/A29/A26/A12/A14/A24 regressions all pass under
  `.build/ui-probe-evidence/astra-a17-primary`. Fixtures are isolated; asset move simulates adoption, not the production store transfer.
  Hardware camera/microphone, full-duration limit, physical gestures, real adoption and server send remain unverified.
