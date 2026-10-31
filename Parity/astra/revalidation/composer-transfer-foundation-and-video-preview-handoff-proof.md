# Composer-transfer foundation and video-preview handoff proof — 2026-10-02

- A30b1 worker `946dc02` integrated as `80b2972`. An in-memory value snapshot separates ordinary compose/edit/reply/quote intent
  from mutable CustomMessage objects; images/documents retain IDs. One-shot transfer requires exact account/chat/topic (nil remains
  distinct), a new current client and unchanged quiescent owner state. Cancel/mismatch/failed retirement retains old ownership;
  commit synchronously retires it before constructing the new owner. ChatVM seeds local dirty intent before publishers/server draft
  hydration and fences retired location use/deinit file deletion/Media dismissal. No persistent schema or TDLib API change.
- Navigation does not yet call this factory. Active/pending voice/video/send/import-sensitive work must stay excluded until its
  ownership barriers are implemented; ordinary-controller picker/transition checks belong to A30b2. Before enabling replacement,
  navigation must accept the transaction before irreversible retirement and process Main plus Chat in one ready cycle.
- References: pinned current/pre-Liquid `ChatInterfaceState/Sources/ChatInterfaceState.swift` 513–523/514–524 and 612–618/565–571
  separate compose/edit/reply/media state. Four Swift files formatted together; primary build
  `.build/logs/xcodebuild/build-Debug-20261002-171549-4184-7097.log` passed without warnings (16s).
  Worker final log copied with `worker-A30b1-` prefix. Audit Simulator PID `4968`: `-ui-probe-composer-restoration` passes actual
  value/transfer/lifetime helpers, isolated selected files, account/topic/client fences, unchanged/busy/cancelled/reentrant state,
  failed-retirement retry, detached mutable message and old-deinit cleanup=0/new-owner cleanup=1. Five readiness/edit/media regressions
  pass beside the result in `.build/ui-probe-evidence/astra-a30b1-primary`. No actual ChatVM construction in this probe:
  seed order and production cleanup wiring are source/build proof only, not foreground Chat recovery.
- A16 worker `44c2c35` integrated as `476f4ec`. Recorder reuses enqueued cleanup when retained result says `originConsumed=true`:
  clear local ownership and dismiss, leaving retry/discard with composer. Cancel during submission cannot discard the transferred
  file; only its obsolete error is suppressed. Unconsumed local preview/Cancel and send-store removal tombstones are unchanged.
- References: pinned current/pre-Liquid `LegacyComponents/Sources/TGVideoMessageCaptureController.m` 1109–1115/1113–1119
  and `LegacyInstantVideoController.swift` 215–257/216–258 transfer capture into outgoing resource ownership. Three Swift files
  formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-171743-5488-28712.log` passed without warnings (8s).
  Worker final log and README preserved with `worker-A16-` prefix and `.build/ui-probe-evidence/astra-a16-worker/README.md`.
- Audit Simulator PID `6029`, `476f4ec`: `-media-probe-video-note-submission-ownership` passes six actual offscreen-recorder
  scenarios with isolated VideoNoteFileStore and native MP4 fixtures. Consumed-retained, Cancel during submit, stale navigation result
  and enqueued paths preserve canonical media/manifest through obsolete Cancel/deinit; retry acquires ownership and exact temporary-ID
  registration succeeds. Unconsumed preview and pending Cancel still delete the local asset once. Seven A17/A30b1/A30a/A24/A14/A12/A26
  regressions pass under `.build/ui-probe-evidence/astra-a16-primary`. No real messages sent, user stores changed or capture hardware
  started. Persisted-recording materialization, ChatVM submit RPC and live gestures remain unverified. Marker scan is empty.
