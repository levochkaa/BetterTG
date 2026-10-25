# A15b2 voice lifecycle checkpoint — 2026-10-02

- `7f53f11` (worker `f12e3d1`) separates interaction, background and audio-interruption suspension. Clearing one reason cannot
  revive another or an older permission/trim/resume/preview/send intent. Background pauses preview and checkpoints the canonical
  PCM/trim/promotion owner. One bounded UIKit time assertion is exact-once, including immediate expiration; expiration does not
  cancel canonical persistence. Foreground does not resume capture, playback or sending automatically.
- `f1721d0` (worker `0251285`) fixes a primary-review finding: background must not wait on upload-action/reply-validation network
  preflight. The checkpoint marker ends when encoded canonical media is durable, before network awaits. A task captured while still
  encoding sees its invalidated send epoch and retains the draft. Accepted RPCs still register their actual temporary ID and retain
  their files. Fallback closed-segment promotion now keeps the route barrier through CPU/store completion. Storage formats unchanged.
- References: pinned current/pre `TelegramUI/Sources/ChatController.swift` 6857–6872 / 5963–5978;
  `Chat/ChatControllerMediaRecording.swift` 460–480 / 470–487 (stop into preview);
  `ManagedAudioRecorder.swift` 448–455 and 522–560 (session deactivation and Ogg pause/resume). Durable disk policy is BetterTG's
  adaptation; source does not establish Telegram observer ordering or identical process-death behavior. TDLib send/reply preflight
  and returned message-ID registration retain the earlier A12/A14 contracts.
- Four worker Swift files and combined nine-file primary set formatted before their builds. Primary combined build
  `.build/logs/xcodebuild/build-Debug-20261002-190401-63298-26208.log`: PASS 11s, zero warnings; follow-up build above also clean.
  On the audit Simulator, sources `f1721d0` / `5ac2810`, PIDs `64668` / `71481`, `-media-probe-voice-lifecycle` and
  `-media-probe-voice-finalization` pass. Proof: `.build/ui-probe-evidence/astra-a15b2-primary`; worker notes/logs retained separately.
- Native isolated proof uses real PCM16/48kHz trim/concatenate, Ogg codec and private recording/send stores: independent reasons,
  route barrier, duplicate/expired assertion, stale intent, failed append, explicit discard, metadata and accepted-ID ownership.
  It neither instantiates a real ChatVM nor emits OS audio notifications/server RPCs. Real microphone/interruption/process suspension,
  ChatVM's suspended network preflight and actual accepted send remain unverified; this does not close those runtime gaps.
