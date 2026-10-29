# Rich-text contact comments — 2026-10-30

Scope: contact attachment comments, from `bf5080ad` on `t3/refresh-goal-prompt`.
Implementation is in this audit's commit. Gallery caption editing remains open.

## Reference and changes

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`, read with `git show`:

- `submodules/AttachmentUI/Sources/AttachmentController.swift`: the shared panel edits the active
  picker's caption; starting editing expands the sheet.
- `submodules/AttachmentUI/Sources/AttachmentPanel.swift` and
  `submodules/AttachmentTextInputPanelNode/Sources/AttachmentTextInputPanelNode.swift`: the input
  grows above the keyboard; deselection ends editing.
- `submodules/TelegramUI/Sources/ContactSelectionController.swift` and
  `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift`: Contact owns its comment,
  initially empty. Gallery separately receives the initial compose text. Contact comments precede
  the cards in the same thread, without a reply; the cards retain the compose reply. The comment
  survives primitive, multiple-contact and extended-vCard paths, including silent/scheduled sends.

AttachmentPanelView can now host the existing FormattedTextView inside interactive glass. It retains
live markdown, formatting, paste, custom-emoji rendering and marked-text handling. Its input grows
from 40 to 160 pt, then scrolls; Send stays at the bottom. Gallery retains its existing read-only label.
Contact owns the attributed comment independently of the main compose draft and commits marked text
before sending. The list reserves the panel's visible height.

AttachmentMessageSequence prepares the optional comment before the selected contacts. It trims and
splits with ComposerTextBreaker at 4096 UTF-16 units, preserving entities and character boundaries.
ChatVM applies the same options/topic to every item, replies only with the contacts, and checks the
account/location and cancellation before each request. Existing draft/reply cleanup remains intact;
the comment does not replace the main compose text. Other attachment callers omit the new parameter.

## Verification

SwiftFormat covered all eight implementation/probe Swift files in one invocation. The UI-tested build
passed in 29 s with `./build.sh build --simulator-id 6DF66290-FE39-475C-91FA-0267B1718DDA`;
complete log `build-Debug-20261030-021709-25526-14755.log` has zero warnings/errors.
Built and installed debug dylibs matched SHA-256
`615e908f42ae903090cccca5f3963f8c0eea205a180b6b20fd9dd9bbb984bc66`.

The first runtime pass found the panel underneath the keyboard: a resting constraint at priority 999
displaced the constrained keyboard guide to 34 pt, while an unconstrained guide measured 335 pt.
Rebinding to the parent merely displaced that guide instead. The final code retains the screen's
guide and lowers the resting constraint to defaultLow, as ForwardMessagesViewController does. Both
guides then measure 335 pt; the input is at screen y=486...526 above keyboard y=539. An intermediate
parent-anchor implementation failed at launch and was discarded; it is not smoke proof.

The shared iPhone 17 Pro / iOS 26.5 Simulator was overwritten by another build during verification:
the installed dylib changed to `6c8c25c87533d8e3658e444eeb4e8b03d702233a16a857c5911f2e37d91c2d22`
and the app relaunched without probe arguments. Remaining checks use the idle iPhone 16 Pro / iOS 26.5,
`6DF66290-FE39-475C-91FA-0267B1718DDA`, in this thread's T3 Device panel, with the final dylib verified.
No account data was copied to that Simulator. Its fresh install's notification request was declined.

On that iPhone 16 Pro, the final contact implementation passed:

- Live typing converted `Hello **bold**` to `Hello bold`. A nine-line comment grew to 160 pt and
  scrolled, with Send fixed at the bottom. Focusing expanded the sheet; the input stayed visible above
  the keyboard. Reduced screenshots and a sampled recording were inspected.
- Schedule cancellation preserved the two selected contacts and all text. Silent Send returned one
  callback with ordered Ada 01/Ada 02, the full comment, bold entity `6:4`, and
  `text:reply=false,contact:reply=true,contact:reply=true`.
- Deselecting the last contact hid the keyboard and restored tabs. Reselecting retained the comment.
  Cancelling sent nothing; a newly opened picker started with an empty comment.
- Searching selected the injected extended Cora 08 card. When Online then double Send in the field
  selector returned exactly one callback with the comment, one vCard and online options. The resting
  accessibility snapshot omitted its visible navigation buttons, so Send used its screenshot position.
- A separate single primitive contact returned its comment and the selected date,
  `date:1793312700,silent:false,id:0`. Totals: three sends and four dismissals, including the cancelled
  picker. All sends were intercepted.
- The freshly written composer-entities probe passed all manual entity types, UTF-16 splitting across
  an emoji, empty-comment/no-contact cases, order/reply flags, and the existing UIKit formatting/undo
  checks. No account store, URL or clipboard operation was required.
- The final flow produced no logged Auto Layout conflict or exception on this Simulator.

Local, non-durable evidence: `/tmp/bettertg-contact-comment-keyboard-final.png`,
`/tmp/bettertg-contact-comment-multiline.png`, `/tmp/bettertg-contact-comment-vcard.png`,
`/tmp/bettertg-contact-comment-final.mp4`, `/tmp/bettertg-contact-comment-final-frames-small.png`,
`/tmp/bettertg-contact-comment-{contact-selection-panel-probe,composer-entities-probe,vcard-result,scheduled-result}.txt`.

The attachment-transition regression probe initially observed the transition before UIKit installed
its incoming view: at 76 ms, gallery=true, file=false, top=File, coordinator=true, animations=true,
scene=foregroundActive. It now waits at most two seconds for that view, then retains the 70 ms mid-fade
check and all subsequent assertions (`99243773`). This changes only DEBUG verification. The final run passed both
live screens/chrome, latest-tab ordering, gallery alpha/insets/appearance restoration, dismissal during
a fade and switching during presentation. The actual Gallery selection flow remains source-reviewed
only on this build; the probe uses the shared panel and navigation with fixture screens.

Final verification, after that probe change: all nine Swift files formatted in one invocation;
`build-Debug-20261030-022352-44032-3633.log`, 21 s, zero warnings/errors. Built and installed dylibs
matched `cc14eebdaa319fd68fbaefa56e0bc94d2c3e76aa9427bd3069edacd2a7dadd03`.
The composer-entities probe passed again. A fresh dark-appearance Contact picker kept its input above
the keyboard and returned the exact `Final build check` comment with one primitive card, ordinary
options and no reply on the comment; one initial Cancel produced no send. Final totals: one send,
two dismissals. Normal relaunch returned to the unauthenticated phone-entry screen. No recording remains
active and no existing account, draft, phonebook or preference was changed.

Final evidence: `/tmp/bettertg-contact-comment-final-dark.png`,
`/tmp/bettertg-contact-comment-final-contact-selection-panel-probe.txt`,
`/tmp/bettertg-contact-comment-final-composer-entities-probe.txt`,
`/tmp/bettertg-contact-comment-attachment-transition-probe.txt`. `git diff --check` passed.

## Limits and next

The fixture intercepts sends and supplies local contacts, including an extended card; it does not
read or change the phonebook. This is not server-delivery proof. Errors/partial sends, preservation
for retry, reply/topic delivery, the existing slow-mode scheduling guard, live IME, iPad/rotation/RTL,
VoiceOver, iOS 27 and physical-device behavior need separate coverage.

Next: Gallery's editable attributed caption and a send-time snapshot through asynchronous media
import, preserving newer compose text and account/destination ownership. A caption must remain owned
by its picker; do not introduce one shared value blindly across attachment tabs. Prior menu/readiness,
Stories and device gaps remain open.
