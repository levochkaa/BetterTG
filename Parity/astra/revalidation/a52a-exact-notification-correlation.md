# A52a exact notification correlation — 2026-10-03

- `6f68229` replaces unrelated-last and shifted-only matching with `RichNotificationTarget`: positive exact account,
  peer kind/ID, ordinary cloud server ID in1...Int32.max, exact TDLib raw ID with zero local/scheduled bits. Invalid metadata
  is rejected before creating a TDLib client. The actual getChat response must match requested chatID and metadata peer;
  newMessage also requires its embedded message.chatId. Every getMessage/history candidate rechecks chat and raw ID.
- Telegram official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`2006 and pre `8e7e5fe`
  same path1770 resolve media through exact message identity. Pinned TDLibFramework `1.8.66-022d6020`,
  `td/td/telegram/MessageId.h`27–75 defines ordinary serverID<<20 and distinct low-bit local/scheduled variants;
  TDLibKit `1.5.2-tdlib-1.8.66-022d6020` notificationTypeNewMessage/NewPushMessage, getChat/getMessage/getChatHistory.
- Independent immutable review passes tree `b6f2bce3` on `bd22603`; four-file format2/4. Wrapper
  `175532-86891-9719` PASS9s, full1573-line log zero warnings/errors. Integration with A53a: joint eight-file format0/8,
  `175914-89505-20180` PASS8s, full1573-line log zero warnings/errors.
- Native at source `c60cd43`, Audit Simulator59EB535C/iOS26.5, PID90125, fresh container
  `372A479D-FC6A-4F8B-BFF8-CB41CBC52013`, target report18:00:04+04 PASS. Actual production helper and TDLib model fixtures
  cover nil/wrong account, invalid/maximum cloud ID, low-bit aliases, peer kind/ID, wrong chat response/message group,
  matching-before-unrelated-last and unrelated-only selection. showPreview=false remains identifiable for the next denial
  stage; identity is not preview permission. No RPC/account-store/notification/INInteraction donation in the probe.
- At the A52a checkpoint, A52b remained open: nested session tasks, timeout/expiry and cache-publication lifetime. This helper/model
  proof does not exercise actual NSE delivery or TDLib RPC. Evidence: `.build/ui-probe-evidence/astra-a52-a53/`.
- A52b1 repair boundary reviewed before implementation: one lifetime authority owns continuation, client bootstrap and
  configure/process/resolver task tickets. Exact raw group-chat prefilter precedes the sole resolver; getChat's type/peer
  validation remains. Cancellation/timeout revokes tickets and synchronous cache-publication authority, then closes on a
  separate utility task without joining pending RPC tasks. No locks across await, continuation resume, task cancellation
  or close. Retirement may wait for already-entered synchronous cache IO; no hard real-time expiry guarantee.
- Pinned TDLibKit `TDLibApi.swift`31051–31069 uses a checked continuation without Swift cancellation propagation;
  manager `closeClients`133–138 waits for clients removal, and queryQueue177–178 removes before the queued client update
  handler necessarily runs. Canceling a Swift Task or completing close is not a callback-drain proof. A52b2 service request
  generation, builder/INInteraction donation and callback ownership remain separate from the session-only repair.
