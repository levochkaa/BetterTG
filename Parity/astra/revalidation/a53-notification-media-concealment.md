# A53 notification media concealment — source finding 2026-10-03

- At `89a9dd2`, `RichNotificationCacheCoordinator.cacheMedia` accepts incoming photo/video/animation through its local
  `mediaCandidate`, which lacks both `isSecret` and `hasSpoiler` guards. Positive server message IDs in cloud private/group/
  supergroup chats can therefore acquire persisted preview bytes. Secret-chat peer mapping returns nil; do not generalize
  this finding to a demonstrated secret-chat delivery.
- NSE `NotificationTDLibSession.swift`450–460 already excludes secret/spoiler MessageContent, but
  `RichNotificationContentBuilder.content`21 and `fallback`88 read the shared cache without eligibility evidence.
  `NotificationService.waitForCachedMedia` has the same read path. Source review demonstrates the bypass path, not
  real push exposure. No actual private/secret content was opened or sent for this finding.
- Telegram official `6ad963e5`, `Telegram/NotificationService/Sources/NotificationService.swift`2006, and pre-Liquid
  `8e7e5fe` same path1770 explicitly exclude `containsSecretMedia` and `MediaSpoilerMessageAttribute` before extracting
  notification media. Preserve that contract with TDLib `MessageContent` flags; no Telegram infrastructure import.
- Next after A51b: bounded app-side eligibility gate before download/cache, deterministic positive/negative cases. Then
  examine persisted eligibility, content edits and NSE fallback authority; a new admission guard alone does not sanitize
  existing entries or prove delayed/cache-only notification delivery. Keep this separate from avatar-worker proof.
- Repair plan reviewed at `fea42b4` before implementation: A53a shared full-message eligibility plus source/chat/raw-message
  work leases. Reject secret/spoiler/self-destruct media before any getChat/download/write; preserve ordinary supported
  positives. Matching content/delete updates and auth/source revocation retire old jobs immediately; every await must
  recheck the captured lease, and older cleanup must not remove a replacement job. This stage does not close the disk/NSE bypass.
- Prerequisites for the remaining end-to-end repair: A52 exact account/chat/peer/raw-message correlation and live-session
  authority. The current unrelated addedNotifications.last fallback and shifted-only ID match cannot certify media under a
  metadata key. Then explicit unresolved/denied/allowed state must govern builder, cache wait and cache publication.
  Under-specified PushMessageContent thumbnails are not positive evidence; fetch exact full MessageContent even when a
  push thumbnail exists. Explicit denial must never become an ordinary nil cache fallback.
- Durable cache target: atomic versioned evidence and bytes bound to account/peer/chat/raw-message/content revision;
  old scoped/unscoped JPEGs stay untouched and unread. Observed edits/deletes revoke evidence and outstanding jobs before
  awaits; only current verified content can republish. Preserve ordinary eligible preview/fallback behavior. Unseen server
  edits and actual remote notification delivery remain separate proof limits, not reasons to disable every preview.
- Planned probes use isolated roots and the actual production policy/lease/attachment-selection seams, with held async
  work and exact receipts. Do not donate synthetic INInteractions or send real notifications for these tests.
- A53a `f74fa77` (worker `3f77fb1`, reviewed tree `55d6883a`) adds shared full-Message policy: photo/video/animation
  require !isSecret&&!hasSpoiler; videoNote !isSecret; selfDestructType/selfDestructIn reject the envelope. Ordinary
  autoDeleteIn does not deny previews. The app preserves photo/video/animation/sticker candidates and placeholder→file.
- `RichNotificationMediaPrewarmer` owns source/chat/raw-message UUID leases. New-message admission and content/delete
  revocation use the same synchronous accepted-TDLib publisher order; an old queued admission cannot revive an edited job.
  Matching edits/deletes, auth nil and source/client replacement revoke before awaits resume. Each await rechecks current
  authority; old cleanup cannot remove a replacement. The actual getChat response also validates requested chatID.
- Worker joint four-file format/final build `175435-85477-13178` PASS10s/full1450-line log zero warnings/errors.
  Initial compile missing a nested @MainActor annotation was repaired, not suppressed. Exact peer review caught and fixed
  a vacuous burst-test oracle: the test now requires and awaits the precise newly admitted task. Integration build above.
- Native same source/PID/container as A52a: media-admission report18:00:05+04 PASS; ordinary families and placeholder
  positives, concealed/self-destruct negatives before injected IO, same-turn new→edit, held getChat/download revocation,
  source ABA/client replacement and own-token cleanup all pass. The production publisher/pipeline uses injected RPC/read/
  cache operations; real TDLib/NSE/durable disk revocation is not demonstrated. No private media or messages sent.
  Cache-scope and avatar-worker regression probes also PASS18:00:05 using real isolated JPEG/filesystem IO.
- Remaining A53b: raw existing media cache, NSE nil fallback and push-thumbnail authority still bypass explicit denial.
  notificationTypeNewMessage.showPreview=false is also not yet enforced by the resolver. Versioned evidence plus bytes,
  known-edit/delete invalidation and explicit unresolved/denied/allowed selection depend on A52b session authority.
  App media work remains uncapped and reads/writes on main; this slice revokes leases, not the underlying TDLib download.
- Follow-up `420ae9f` rejects zero/negative, low-bit local/scheduled and out-of-range raw IDs before app prewarmer getChat/
  download/read/cache. It derives the persisted server-message key once from the admitted ordinary cloud ID. Pinned
  MessageId.h27–75 supplies the encoding; maximum Int32 server ID remains valid. Independent exact review passes tree
  `c6bf1b7c`; joint two-file format0/2, build `180821-97791-18988` PASS10s/full1454-line log zero warnings/errors.
- Native follow-up at `420ae9f`, same Audit Simulator/runtime, PID2426, fresh container
  `1EF3238E-91C2-4DD2-94CF-5B75DD6ECD24`, media-admission report18:10:29+04 PASS. Negative IDs cause no injected IO;
  maximum valid ID round-trips the cache key. Saved `media-cloud-id-native.txt` with the other A52/A53 evidence.
- A53b must also treat pinned `pushMessageContentHidden` (td_api.tl8537–8538) as explicit denial before fetchMessage:
  the current nil-candidate path can fetch full media/body despite a hidden push. Backend
  `apns-payload-mapper.service.ts` forwards loc_key as metadata.event without independent preview permission. This is
  source evidence, not demonstrated push exposure. Content eligibility and notification preview permission are distinct.
- A53b1 repair boundary reviewed before implementation at `51d7174`: represent unresolved/denied/allowed media explicitly;
  hidden/showPreview=false must withhold body overrides as well as attachments. Scan every exact notification in the batch
  before admitting the sole resolver. Later denial/edit/delete and publication/finish must use one lifetime authority so a
  previously accepted resolver cannot publish after known denial. Require exact full Message admission even with push thumbnails.
- A53b1 removes raw-JPEG reads from builder/fallback/cache-wait, preserves fresh eligible media and normal text/title/avatar/
  quick reply, and adds injected production decision/race proofs without real notifications or donations. It leaves old cache
  files untouched. Transitional limitation: unverified cache-only media is withheld. This is not complete A53 parity.
- Mandatory next A53b2 restores ordinary verified cache-only previews: atomic versioned evidence+bytes, exact account/chat/
  ordinary raw-message identity, separate preview permission, cross-process revision arbitration and observed edit/delete
  invalidation even without an active job. Missing/evicted evidence must reject late commits. Existing raw JPEGs remain unread;
  full Message media eligibility alone must not be treated as showPreview permission. Unseen server edits/settings stay unverified.
