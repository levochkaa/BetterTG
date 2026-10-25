# A53b1 explicit preview evidence — 2026-10-03

- `2451dd3` (worker `dcf727f`, exact reviewed tree `33dcf2fa`) separates denied/unresolved/allowed media. Every media push
  requires the exact full Message, even if it carries a thumbnail. Full envelope self-destruct and media secret/spoiler flags
  are checked; missing evidence stays unresolved. Ordinary full-message families, no-thumbnail caption and chat auto-delete
  remain permitted. Original body is preserved for denied/unresolved decisions; no generated caption can bypass the decision.
- Every matching entry in an addedNotifications batch is scanned before resolver admission. Hidden/showPreview=false,
  content/edited/delete and exact previously bound updateNotification replacements retire the same session authority that
  owns publication/finish. A held old result cannot overwrite the denied result or publish. Wrong client/chat/raw-message/group
  identities cannot deny it. This linearizes at the lifetime lock, not callback/decode entry; post-retirement updates are unobserved.
- NSE builder/fallback/cache-wait no longer read raw media JPEGs; NSE no longer writes them. Builder accepts only explicit
  allowed bytes and clears pre-existing attachments. Existing disk files are untouched; avatar caches and Intents identifiers
  are unchanged. Concealment retains the existing metadata quick-reply fallback; it does not imply chat send permission denial.
- Pinned TDLib td_api.tl8537–8538/8716/8730 supplies Hidden, showPreview and the weaker push model. updateNotification omits
  chatID and therefore requires a group already bound by an exact target event. Telegram media concealment references above
  still apply. Caption entity spoilers are a separate remaining body issue, not covered by media.hasSpoiler.
- Joint worker nine-file format; final build `190516-81039-5600` PASS7s/full1458 lines zero warnings/errors. Explicit Gate
  MainActor isolation fixes the first probe build warning without suppression. Primary joint eleven-file format0/11;
  integration `190831-85528-20489` PASS17s/full1601 lines zero warnings/errors. Exact independent and primary reviews pass.
- Native source `2451dd3`, Audit59EB535C/iOS26.5, PID87313, fresh container `96D8ED57-42F8-4151-8B55-E846C09499F0`:
  preview report19:09:41+04 PASS. Production policy/lifetime fixtures cover all ordinary full media, push thumbnail requiring
  fetch, hidden/showPreview/media flags, both batch orders, bound replacement, missing/wrong identity, held fetch/download
  revocation and exact late-task publication/finish rejection. Fixture RPC/donation effects0; actual NSE/builder/APNs unverified.
- Same run all six request/lifetime/target/admission/cache/worker regressions PASS19:09:40–41. idb preinstall count22; wrapper
  preserved host focus and borrowed Simulator. Evidence: `.build/ui-probe-evidence/astra-a52-a53/preview/`.
  Transitional limitation: unverified cache-only media remains withheld. A53b2 restoration is mandatory, not optional polish.
- A53b1a plan at `2451dd3`: media.hasSpoiler does not cover FormattedText caption entities. The current body formatter reads
  caption.text directly for photo/video/animation/document, potentially replacing a safe APNs body with concealed text.
  Preserve original body whenever its caption contains textEntityTypeSpoiler, without denying an otherwise eligible attachment.
  Keep plain/non-spoiler caption enrichment; test the shared production caption gate with actual TDLib entities. No range
  rewriting, new notifications or donation fixtures. Pre-Liquid `ChatMessageNotificationItem.swift`219–223/448 retains spoiler
  entities and hides their text for in-app notifications; this is concealment reference, not proof of remote APNs formatting.
