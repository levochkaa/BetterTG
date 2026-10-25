# Voice lifecycle preservation proof — 2026-10-02

- A11 scope: navigation/permission teardown stops capture and preview without calling explicit discard. Main-actor registration
  retains canonical PCM/trim/adoption work and makes a reopened account/chat/topic route await it. A lifecycle generation rejects
  pre-suspension permission/resume/send/trim-audio continuations even after UI re-enablement. A forced teardown trim save never
  starts preview audio. Recording and send storage formats, route/reply/caption/waveform/revision contracts remain unchanged.
- Independent delta review identified the reopen barrier, stale intent revival and forced-trim autoplay gaps; all three were
  repaired. A12–A14, video lifecycle A15 and system interruption handling are not claimed fixed by this slice.
- One SwiftFormat invocation covered the five changed Swift files. Final warning-free `./build.sh build` log:
  `.build/logs/xcodebuild/build-Debug-20261002-150301-32416-21283.log`; no warnings/errors in the full output.
- `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B --
  -media-probe-voice-preservation -ui-smoke-voice-gestures`, iPhone 17 Pro / iOS 26.5, PID `36834`.
  The user-authorized Simulator reaches real Saved Messages. The deterministic barrier/epoch probe reports restore-waits,
  canonical-revision, account-isolation, barrier-cleanup, suspend-invalidates-intent, reenable-keeps-old-intent-invalid and
  new-intent-allowed. Output: `.build/ui-probe-evidence/astra-voice-preservation-final-probe/voice-preservation-probe.txt`.
  This tests production coordination primitives, not an injected full ChatVM PCM-save race or live rights mutation.
- Production idb flow: hold→lock→pause, trim `0…21.0189435044s`, Back→reopen and wrapper relaunch all retain the same local
  draft `A4895271-1B10-484A-BD3D-8A7D74D60BB9`, media filename and edit revision 1. Sorted canonical manifest SHA-256 after
  Back and relaunch: `63d4ca98ab895c0f2013986a48f564e5c4b03edb45ed7f6a6e128b3c3ab9abd2`.
  Evidence: `.build/ui-probe-evidence/astra-voice-after-{back,relaunch}/`, `astra-voice-after-relaunch.png` and filtered hierarchy.
  The final build again restored trim `0:00.0…0:21.0` with Play, not active playback. Reply was nil; reply preservation is source-only.
- A second real hold→lock followed by Back during capture produced paused `27.6s` preview after reopen, not a continuing recorder.
  Manifest/WAV `5753F35D-1BE7-43F6-8713-C20DE301B67B` were present; proof is in
  `.build/ui-probe-evidence/astra-voice-active-back/` and `astra-voice-active-back.png` (visually inspected).
  Explicit Cancel/Delete removed each agent-created draft and WAV; the recording-draft directory was empty after both deletions.
  No messages were sent, no chat rights changed, no user drafts removed, no database reset and no Simulator shutdown occurred.
