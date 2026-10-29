# Recent File client recovery — 2026-10-30

Scope: retain the active File attachment picker across same-account client replacement, from
`9e9a8368` on `t3/refresh-goal-prompt`. Implementation is in this audit's commit. Full parity remains open.

## Reference and behavior

Official Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:
`submodules/TelegramUI/Components/AttachmentFileController/Sources/AttachmentFileController.swift`
owns selection and attributed caption in the cached controller; `ChatControllerOpenAttachmentMenu.swift`
retains that controller for the attachment session. Client replacement is BetterTG-specific. This slice
extends the existing ChatVM/navigation restoration and Gallery recovery contracts to the active File tab.

- Freeze input and dismissal when replacement starts. Wait for any old send receipt and open context
  menu to finish before moving the real picker. Apply accepted IDs first; a successful old send closes
  normally. Nothing is resent automatically.
- Retain the ordered unsent selection, attributed caption, retry option and cached Gallery. Remove a
  caption only if its last document was accepted. An unidentifiable receipt keeps retry disabled.
- Transfer the send session only to the same nonnil account, chat and route topic with a different
  client. Change only its client ID; retain resolved destination topic, reply/quote and default option.
  An All Messages route can retain a reply targeting a forum topic. The original session stays unchanged.
- Release old navigation chrome and Gallery's outside-tap recognizer after dismissal. Rebind File's
  send, input and tab callbacks on presentation by the replacement ChatView. A second replacement
  before presentation carries the frozen state onward. Translate Gallery's initial draft revision from
  the captured composer snapshot.
- Cancel old list/search tasks and reject responses from their client generation. A late schedule-picker
  callback cannot send through the replacement binding. An unconfirmed date picker closes with its old
  presentation; the already committed retry option remains.

The UI probe exposed a shared chrome defect: a retained controller installed before sheet presentation
reserved 54 pt, while its presented bar needed 64 pt. Chrome now updates its reserved safe-area height
during layout as well as item refresh. The change follows the existing sheet-padding rule; it adds no
new visual dimensions.

## Verification

All six changed Swift files were formatted together. Final wrapper build passed in 21 s:
`build-Debug-20261030-033707-55541-20870.log`; the complete 941-line log had zero warnings/errors.
Built and installed debug dylibs matched SHA-256
`7022621868b10df8246bb211fd1b9d9557b02c0f6232b6bb85ee514239e03f5d`.

Device: this thread's unauthenticated iPhone 16 Pro / iOS 26.5 Simulator,
`6DF66290-FE39-475C-91FA-0267B1718DDA`, driven through T3 Device and its pinned agent-device CLI.
`-ui-probe-file-attachment` uses the real picker and controlled local send callbacks. It rebinds the
controller to a new callback generation while retaining the same actual TDLib client; it does not
exercise authenticated ChatView/ChatVM replacement or send Telegram messages.

| Final-build check | Observed result |
| --- | --- |
| Scheduled full failure during replacement | Two files and `Retry bold` with bold entity `6:4` survived. Generation 1 retried the same IDs, entities, last-caption slot and exact date `1793317200`; double Send produced one request. |
| Partial online send during replacement | Old generation accepted file 2; only file 1 remained, with an empty caption. Gallery/File roundtrip retained it. Generation 2 sent only file 1 with the same online option; double Send produced one request. |
| Successful old send during replacement | One immediate request completed and closed File. Recovery count stayed at 2; no reopening or second request. |
| Replacement requested with Select menu open | The picker stayed frozen while the menu remained visible. Closing it allowed transfer; search, Gallery/File tabs and Cancel worked afterward. Send count stayed unchanged. |
| Chrome and panels | Selection recovery retained `64 → 64` pt top inset; search recovery retained `114 → 114`. Bottom inset stayed 66 pt, with one attachment panel. Restored File screenshots showed the selected remainder and normal search state. |
| Deterministic state checks | Two successive client replacements, original-session immutability, forum destination vs route, reply/quote/nil and default silent option; rejection of wrong account/chat/topic/source client and unchanged client. Existing caption/receipt checks also passed. |
| Attachment transition regression | Live source/destination chrome, latest pending tab, restored alpha/insets/appearance, discarded pending tab on dismissal, switching during presentation and retained-controller re-presentation all passed. |

Earlier fixture runs did not trigger renewal because the new buttons fell through to the appearance
handler; they are not recovery proof. The subsequent `033432` build proved partial silent retry but
exposed the 54/64 pt discrepancy. Only the final build above proves the corrected inset behavior.

Bounded Simulator logs contained no matching Auto Layout conflict, presentation warning, terminating
exception or probe failure. Normal launch was restored to phone entry. Local, non-durable reports and
screenshots are in `/tmp/bettertg-file-recovery-audit/`; they contain fixture data only.

## Limits and next

Actual same-account TDLib renewal, ChatView coordinator integration, source-message refresh, permission
changes, server receipts and delivery remain source-reviewed rather than exercised on an authenticated
account. Generation rejection for late search/date callbacks and repeated replacement before ChatView
presentation also have source/state proof only. Hidden File state waits for its tab to become visible;
this slice does not add recovery for every attachment tab or process death.

Next: dedicated-account Gallery/File renewal and delivery/error verification, then the remaining
menu/Stories/device gaps. IME/custom emoji, accessibility operation, RTL, Dynamic Type, iPad, iOS 27 and
physical-device behavior remain unverified. This checkpoint does not complete the parity goal.
