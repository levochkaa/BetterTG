# Exact media-draft delivery and client streams — 2026-10-02

- A12 worker `2ccdb9b` integrated as `83d0fd4`: `ChatDraftDeliveryKey` freezes account/chat/send topic independently of the
  owning UI route. Stores reject simultaneous enqueue by either route or delivery, require a unique outcome candidate and consume
  early evidence only after exact temporary-ID registration. Registration is persisted before cleanup; arbitrary-ID fallback is
  removed. Legacy account binding preserves the base route. Existing JSON contracts and recording-origin ownership remain intact.
- Reference: pinned current/pre-Liquid `TelegramCore/Sources/State/PendingMessageManager.swift`, account-owned manager
  (218/251 current; 213/239 pre-Liquid), immutable message request ID (192/187), pending-ID contexts (409/258), thread context
  (640/462). TDLib 1.8.66 `updateMessageSendSucceeded/Failed`, `oldMessageId`, delivered `Message.topicId`; no infrastructure port.
- Primary one-call SwiftFormat covered all eight files (`0/8` changed); warning-free wrapper build:
  `.build/logs/xcodebuild/build-Debug-20261002-153825-17942-30766.log` (9s). Worker log is preserved with `worker-A12-` prefix;
  scope/commands/limits are in `.build/ui-probe-evidence/astra-a12-worker/README.md`.
- Safe Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, wrapper PID `18527`, `-media-probe-draft-outcomes`:
  `.build/ui-probe-evidence/astra-integrated-draft-outcomes/draft-outcomes-probe.txt` passed voice+video, ordinary/explicit/all-messages
  early/late success/failure, original route, wrong account/chat/topic/ID, duplicate old manifests, both enqueue gates, exact-ID
  relaunch, unresolved pre-registration crash, legacy base-route migration and unrelated draft/file preservation.
  This uses real store methods and disk manifests in disposable UUID directories with synthetic media bytes; no server sends.
- A18 worker `b2e33d2` integrated as `92a02d9`: every activation owns separate file/delete subjects with immutable account/client
  provenance. Retained publishers cannot follow later account/client replacement. Bootstrap remains inert; A13 and the active-client
  gate are unchanged. All three deletion consumers were source-checked. The sole cherry-pick conflict retained both DEBUG probe hooks.
- Reference: pinned current/pre-Liquid `AccountStateManager.swift` (322–324/308) and `ChatListSearchListPaneNode.swift` (4814/4650)
  use account-owned deletion streams. TDLib `updateFile`, `updateDeleteMessages`; range clients and numeric-ID API stay unchanged.
- Primary one-call SwiftFormat covered all three A18 files (`0/3` changed); warning-free wrapper build:
  `.build/logs/xcodebuild/build-Debug-20261002-154003-19429-13561.log` (11s); worker log preserved with `worker-A18-` prefix.
- Integrated PID `20467`, `-media-probe-client-streams -media-probe-update-source -media-probe-draft-outcomes`: all passed.
  `.build/ui-probe-evidence/astra-integrated-client-streams/client-streams-probe.txt` reads distinct real 64-byte files through retained
  A/B/replacement-client range coordinators with identical file IDs and observes isolated deletion subscriptions. Own-stream byte arrival
  is the ordering barrier; unexpected backend fetch fails. Stale/nil provenance and bootstrap events are rejected.
  `astra-integrated-client-provenance/update-source-probe.txt` repeats A13 generated-dispatch/delayed-delivery proof;
  `astra-integrated-client-drafts/draft-outcomes-probe.txt` repeats A12 on the combined product. Real Saved Messages remained visible
  before installs; no account switch, user-store reset, message send or Simulator shutdown occurred.
- Limits: isolated stream/store probes are not live multi-account server delivery or active system PiP. Legacy voice/video codec probes
  were updated and compiled but not rerun here; the new probe avoids their shared-store cleanup paths. Crash before exact ID registration
  preserves an unresolved enqueue, not automatic recoverability. A14 canonical finalization ownership, callbacks rejected by the inactive
  client gate, A15–A17 video lifecycle and A19 restoration remain open.
