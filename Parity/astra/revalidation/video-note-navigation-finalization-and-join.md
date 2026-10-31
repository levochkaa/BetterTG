# Video-note navigation finalization and join — 2026-10-02

- A15a worker `64c47dc` integrated as `aeb9b4f`: navigation registers an exact account/chat/topic barrier synchronously, freezes
  capture input and joins the sole manual/automatic finish owner. A UI-independent finalizer owns native output → canonical
  recording adopt/append; ChatVM waits before reading drafts. Existing draft/reply/topic/revision survives failed append.
  Explicit Cancel remains destructive; Cancel/state callbacks from a detached preserved recorder cannot reclaim the restored draft.
- Capture state carries its original generation; old callbacks cannot revive dismissed UI. Native terminal failure settles the
  join. The fixture originally named navigation-then-background actually injected capture failure; A15b1 below corrects that name
  and separately tests background preservation. This historical slice alone did not preserve the new segment on background.
  No changes to `InputMessageVideoNote`, send/outcome manifests or TDLib delivery matching.
- References: pinned current `VideoMessageCameraScreen.swift:457–483` waits for stop result; current/pre-Liquid Legacy capture
  output handoff at 1109–1116/1113–1120 and interruption completion at 1349–1356/1353–1360. ChatController foreground handling
  at current 6857–6872/pre 5963–5978 calls `stopMediaRecorder`; `Chat/ChatControllerMediaRecording.swift` 460–480/470–487 selects
  preview for active audio/video. Legacy's separate background observer at 190–198 dismisses. Source does not establish callback
  ordering or universal deletion; on-disk/process-death recovery is a separate BetterTG durability policy.
- Primary first build `.build/logs/xcodebuild/build-Debug-20261002-174405-45697-8734.log` passed without warnings (25s).
  Initial runtime failed before its first finish gate: `recordingUnavailable`, then timeout. Diagnostics `beb1b3d`/`3f9e8ea`
  bounded the failure and exposed ownership. Fixture correction `60a29cb` (worker `4a224e7`) loads the real recorder view before
  installing capture, matching production `beginCapture`; its gate also reports an early terminal result instead of hanging.
  The exact prior cancellation cause is unproved. No production workaround was added to make the fixture pass.
- Final primary build `.build/logs/xcodebuild/build-Debug-20261002-180134-71658-8387.log` passes without warnings (9s).
  Audit Simulator PID `72550`, `-media-probe-video-note-preservation`: all eight actual-recorder/native-H264-AAC/store cases pass
  for manual/auto ownership before/after finish, pending append, stale-revision failure, explicit Cancel, route isolation and later
  capture failure (original output called it background termination). Evidence: `.build/ui-probe-evidence/astra-a15a-primary`;
  initial timeout/sample and the original output are retained there.
  No user store, real recording, camera permission or server send was touched. Physical capture, rapid-navigation gestures,
  suspension grace time and process death remain unverified.
