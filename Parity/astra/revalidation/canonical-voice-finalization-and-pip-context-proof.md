# Canonical voice finalization and PiP context proof — 2026-10-02

- A14 worker `a8d04c2` integrated as `878eafb`. Six Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-155910-46801-26110.log` (14s). Worker log is copied with `worker-A14-` prefix;
  design and proof limits: `.build/ui-probe-evidence/astra-a14-worker/README.md`.
- Voice store claims canonical runtime ownership before encoding, fences stale snapshots/tokens, uses unique attempt outputs and
  persists the accepted temporary ID before UI-generation checks. Native cancellation is joined before ownership release; preflight
  failures can retry, ambiguous post-RPC failures retain unresolved ownership. Metadata/delivery contracts and A12 gates stay intact.
  Current/pre-Liquid `ChatControllerMediaRecording.swift` (344–356, 735–760 / 354–366, 735–766) and
  `PendingMessageManager.swift` (218–251, 409–438 / 213–239, 258–282) anchor preserved ownership and captured send context.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `47929`:
  `-media-probe-voice-finalization -media-probe-draft-outcomes` passed. Results in `astra-a14-primary/voice-finalization-probe.txt`
  and `astra-a14-draft-regression/draft-outcomes-probe.txt` under `.build/ui-probe-evidence`. Real native Ogg encoding, suspended
  worker/RPC gates, duplicate claim/discard rejection, stale token/adoption, exact-ID outcome, pre-registration retention,
  process-local lease recovery and unrelated-file preservation run against disposable isolated stores. This does not send messages.
- Production UI on `878eafb`: empty recording/send stores; own hold→lock→pause yielded a 42.06s preview. The existing DEBUG
  `-ui-smoke-voice-preview-send` bypassed the send RPC after real promotion/encoding. Own draft
  `CDD62EC0-0614-4481-B007-119AD74DD113` became `isEncoded=true`, duration 42, no enqueue time/temp ID. Manifest SHA256
  `bbf6973377392f25435894ca0bf6423deb279d1600cb2261b597cca8021b6fe4`; captures and manifest/Ogg backup are in
  `astra-a14-ui`. The no-send alert intercepted Back, so navigation-during-encode is not claimed by this UI sequence.
- Reinstall to combined `1fd5c61` changed the container from `CC9310EE…` to `D630B63A…`; the loader deleted this manifest,
  left the Ogg, and restored an empty composer. `before-relaunch`/`after-relaunch` plus `restored.png` reproduce A26. This is a
  pre-existing absolute-URL persistence defect, not passing relaunch proof. Only an agent-created draft was affected; no user draft
  was deleted. Its backup remains available for recovery and the follow-up test. Recording-preview relative storage is separate.
- A19 worker `1ea2594` integrated as `1fd5c61`. Five Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-160148-52841-23853.log` (20s); worker log copied with `worker-A19-` prefix.
  Freeze playback client/location/ranges/deletion stream, preserve route callbacks separately, rebind only the originating profile
  tab, revoke on every client activation, and bound each restoration completion to one terminal callback. Revoked pending/active
  PiP retains its controller through the stop barrier. References: pinned `UniversalVideoGalleryItem.swift` current context
  734–754/restoration 889/retained navigation 3150–3214; pre-Liquid 938–958/1093. No Telegram infrastructure was copied.
- Combined PID `55486`, `-media-probe-pip-context -media-probe-gallery-owner -media-probe-voice-finalization
  -media-probe-draft-outcomes`: all passed. `astra-a19-context/pip-context-probe.txt` covers frozen topic/nil-topic authority,
  same owner/view, route loss, same/changed-tab pagination, account/client replacement, pending/active stop, no stale reattach and
  exactly-once completion. `astra-a19-owner/gallery-playback-owner-probe.txt` repeats real AVFoundation/FFmpeg owner handoff,
  range/session continuity and lifecycle/adapter checks; voice/draft regressions are in `astra-a19-voice-regression` and
  `astra-a19-draft-regression`. Probe context uses injected client identity; actual TDLib action transport and real
  `activate(notify:false)` are source-reviewed, not server/lifecycle-exercised. `pip-supported=false`: active system PiP still
  requires a capable device. Marker scan over production/dependencies is empty; no Simulator shutdown or account reset occurred.
