# Recent File selection and captions — 2026-10-30

Scope: the chat attachment sheet's recent File list, from `80154824` on `t3/refresh-goal-prompt`.
Implementation is in this audit's commit. Full parity remains open.

## Reference and implementation

Official Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:

- `submodules/TelegramUI/Components/AttachmentFileController/Sources/AttachmentFileController.swift`:
  immediate single-file tap; Select in the context menu; ordered source-message selection, numbered
  indicators, selection count, independent caption, search dismissal and source-message refresh before sending.
- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift`, `.file`:
  a cached controller for the attachment session, empty initial caption for a normal send, attributed
  caption on the last selected file, and document grouping. BetterTG bounds every album to ten items.
- AttachmentController/AttachmentPanel and the shared BetterTG input/send-capability components:
  attributed input in interactive glass, multiline growth above the keyboard and destination-specific options.

Chat opts into selection; Poll's existing consumer remains an immediate single pick. Source identity is
`(chatID, messageID)`, so different messages containing the same file remain distinct. File owns its
caption independently of the main composer. The cached controller retains caption and selection through
Gallery/File tab changes without installing another panel or adding another safe-area inset.

Send commits marked text, blocks duplicate sends and dismissal, and displays progress. The sheet stays
open until local TDLib enqueue completes. This deliberately differs from Telegram's earlier dismissal:
a local failure can retain the unsent selection without rebuilding the sheet. The send session freezes
account/client, chat/topic, reply including quote, and the default posting option before asynchronous work.
Retries retain that destination/reply even after a partial send clears the main composer reply. Each group
revalidates permission and destination. Source messages are refreshed through the captured client.
The caption uses the existing composer entity conversion and length validation; it belongs only to the
last document. The main composer's text, media and forward are not consumed.

Receipts remove specific accepted source IDs. A partial album can omit a middle item, so matching uses
document identity and caption rather than assuming an accepted prefix. A caption leaves the retry only
when its last document was accepted. Unknown receipts disable retry within that picker to avoid duplicates.
The reply is cleared only if its current ID and resolved quote still match the snapshot. A full failure
retains the selection, attributed caption and chosen silent/date/online option. No automatic resend occurs.

The shared menu supports silent sending, When Online, dates and Saved Messages reminders. At the pinned
Telegram reference, File's `schedule` body is commented out and its multi-completion drops schedule time.
BetterTG uses the working Gallery/Contact capability path here; date and online support are a deliberate
completion of that common behavior, not a claim that the upstream File implementation already works.
System Files import and edited-media selection keep their existing paths.

## Verification

All six changed Swift files were formatted together. Final wrapper build passed in 23 s:
`build-Debug-20261030-031623-22794-11817.log`, zero warnings/errors in the complete log.
Built and installed debug dylibs matched SHA-256
`be214885f395840aa983482b54cd7d6e92dbcfeeef607926ee4f976e404932bc`.
The device was this thread's unauthenticated iPhone 16 Pro / iOS 26.5 Simulator,
`6DF66290-FE39-475C-91FA-0267B1718DDA`, through the T3 Device panel and pinned agent-device CLI.
All sends used the DEBUG fixture's local callback; no Telegram messages, account data or contact data changed.

| Build / dylib prefix | Observed result |
| --- | --- |
| `030826` / `18c18aa1` | Select through the real menu; order `1,3,2`; bold `6:4`; silent request with caption only at index 2. Poll holding/releasing one row returned one file. This build exposed an invisible selection badge. |
| `031213` / `4bb394f5` | Selection badges visible. Partial online send of `1,3,2` accepted 3 and 2; retry contained only 1, empty caption and the same online option. Search for File 02 → Select closed search. Three-line bold caption survived Gallery/File roundtrip and schedule cancellation. Full scheduled failure retained text/entities; double Send produced only one retry. The initial dark-theme fixture changed only its host; its light sheet was not dark-mode proof. |
| `031623` / `be214885` | Final selected rows retain their filenames in accessibility. Actual dark sheet and keyboard show the numbered selection and three-line bold caption. Two-file scheduled failure/retry preserved bold `6:4`, last-caption index 1 and the exact date `1793316000`; double Send produced one callback. Poll picked one file, immediate chat double-tap produced one empty-caption request, and no-schedule capability showed only silent sending, which returned `silent=true`. |

The deterministic probe passed last-item caption/entities, nonprefix receipts, two sources sharing a
file, rejection of an unknown receipt and retaining the original retry context/default option, including
nil reply. These are state/receipt checks, not authenticated TDLib execution.

The badge initially lived under UIKit's configured content. It now belongs to the cell and is brought
above its content during layout. The row explicitly retains the filename as its accessibility label.
This made an unqualified CLI filename selector ambiguous between cell and text; a fresh snapshot and
`role="cell"` resolved it. The fixture now applies appearance to its presented navigation controller.
A shell argument initially inserted literal `\\n`; re-entering actual newlines verified real multiline layout.

Local, non-durable evidence is under `/tmp/bettertg-file-audit/`: initial/final request reports,
`bettertg-file-final-selected.png`, `bettertg-file-partial-retry.png` and `bettertg-file-final-dark.png`.
Bounded Simulator logs contained no Auto Layout conflict, presentation warning or terminating exception.
Normal launch was restored to phone entry after the fixture.

## Limits and next

No real TDLib enqueue, server delivery, partial album response, deleted source message, permission change,
forum reply/quote or account/client replacement was exercised. Those paths have source review and the
listed deterministic checks only. A retired client is rejected; this File selection is not transferred to
a replacement ChatVM, unlike Gallery recovery. Process-death recovery, custom emoji/IME, caption limits,
large batches, VoiceOver operation, RTL, Dynamic Type, iPad, iOS 27 and physical-device behavior remain
unverified. System Files staging and recent-file replacement while editing are outside this slice.

Next: dedicated-account Gallery/File send/error/client-renewal verification and File recovery transfer;
then the remaining menu/Stories/device gaps. This checkpoint does not complete the parity goal.
