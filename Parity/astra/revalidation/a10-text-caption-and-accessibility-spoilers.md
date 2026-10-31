# A10 text, caption and accessibility spoilers — 2026-10-02

- `f2bbe89` (worker `f5c69bd`) adds display-only concealment. Immutable account/client/chat/source-message and exact formatted
  payload own cell-lifetime revelation; edit/reuse/source replacement invalidates callbacks. Hidden glyph/link/code/custom-emoji
  ranges stay concealed, first tap reveals, second may activate. Non-actionable bold/italic no longer swallows a later link action.
  Actual glyph hit testing excludes padding/status. Hidden custom emoji is not requested; generation checks fence old first frames.
- Body and audio/document album captions share the reveal contract, with independent member states. Parent and text-view AX use
  redacted labels; text-view value is explicitly empty. Reply/quote previews stay concealed while retaining navigation/expand.
  Chat summaries redact only the formatted segment, preserving attachment prefixes. Draft/write values and global formatter unchanged.
- The first integrated iOS probe failed on a split surrogate: `Range(NSRange,in:)` accepted an inner UTF-16 index. `f87ad74`
  validates start/end scalar boundaries explicitly, rejects overflow and split pairs, retains valid combining-scalar ranges, and
  fails malformed spoilers closed across nonempty text. Both split-start/end and valid full-emoji/combining cases now pass. The
  initial failing result is retained; a warning-free build alone did not catch it.
- References: pinned current/pre `ChatMessageTextBubbleContentNode.swift` 177–188,1202–1205 / 197–206,1119–1121;
  `InteractiveTextNodeWithEntities.swift` 350; `ChatMessageReplyInfoNode.swift` 486,503,880–891 / 458,475,801. TDLib pinned
  `FormattedText/TextEntity` uses UTF-16 ranges; source models and send contracts remain intact. A20 media concealment is separate.
- Final two-file SwiftFormat + build `.build/logs/xcodebuild/build-Debug-20261002-193330-78095-31536.log`: PASS9s, zero warnings.
  Audit Simulator source `f87ad74`, PID `78753`, `-ui-probe-text-spoilers`: PASS actual UIKit glyph layout/action dispatch,
  unchanged reveal geometry, parent/child AX, reply/quote/summary, independent state/reuse/source gates and emoji admission.
  Proof `.build/ui-probe-evidence/astra-a10-primary`; worker notes separate. Actual emoji decoding, full album layout and live
  spoiler-message touch/VoiceOver smoke remain unverified. URL/clipboard actions were captured, not executed; no server writes.
