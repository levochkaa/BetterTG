# Gallery attributed captions — 2026-10-30

Scope: Gallery caption ownership through Photos import and attachment send, from `b99a754d` on
`t3/refresh-goal-prompt`. Implementation is in this audit's commit. Full parity remains open.

## Reference and changes

Official Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:

- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift`, `presentMediaPicker`:
  Gallery receives the initial attributed compose text and owns its caption separately from other tabs.
- `submodules/MediaPickerUI/Sources/MediaPickerScreen.swift`, `sendSelected`, `schedule` and
  `legacyCompletion`: scheduling precedes sending; the editing context supplies the send caption.
- AttachmentController, AttachmentPanel and AttachmentTextInputPanelNode: a growing input above the
  keyboard; focusing expands the sheet. Contact's independent comment remains unchanged.

Gallery uses the shared FormattedTextView in interactive glass, initialized once from the compose
draft. Send commits marked text and captures entities, caption position, mode and schedule. Cancelling
the date picker keeps Gallery open. File/Poll/Web App callers keep their existing selection contracts;
edited-media replacement receives the initial attributed caption and validates the original message ID.

AttachmentMediaSendState owns the imported files, caption, original draft text/revision, reply, forward
and resolved destination. Import no longer replaces the main composer's files or reads its newer text.
It refuses an incomplete Photos result or a busy composer. ChatVM validates the current destination,
uses the captured caption for the first item and preserves the existing upload leases, album batching,
spoilers and send options. Only the unchanged original draft may be cleared. Captured nil reply/forward
values stay nil. Send-flight does not borrow unrelated main-composer views.

Local failure reopens the retained Gallery. Confirmed items leave the retry selection; a caption that
already went out is cleared. Unaccepted imported files are released, while message leases protect files
TDLib still needs. Same-account client replacement transfers the pending Gallery recovery and rebinds
its callbacks and emoji client; draft revisions are translated only for the unchanged source draft.
Leaving the account/route never sends the stale request. There is no durable Gallery recovery after
process death.

## Verification

All 12 changed Swift files were formatted in one invocation. Final wrapper build passed in 22 s:
`build-Debug-20261030-025645-85931-28856.log`, zero warnings/errors in the complete log.
Built and installed debug dylibs matched SHA-256
`cbc81ba90803eff5a71ac2b25a91f8bc875bd3b7ca0df7c3bd24ea2bc17635e2`.
The device was this thread's iPhone 16 Pro / iOS 26.5 Simulator,
`6DF66290-FE39-475C-91FA-0267B1718DDA`, through the T3 Device panel and its pinned agent-device CLI.
The install remains unauthenticated. Only two generated test photos were imported; no user account
data was copied or changed.

Build-specific checks:

| Build / dylib prefix | Observed result |
| --- | --- |
| `024138` / `0d7ae71a` | Multiline input above keyboard, live bold `6:4`, schedule cancellation preserving two photos, Move Caption Up and silent send request with two imported files and source-ID mapping. This intermediate build had a capture warning, fixed before final validation. |
| `024932` / `94425ee4` | Deselect → File → Gallery → reselect retained `Kept caption`; Send as File returned that text and one mapped import. |
| `025058` / `6f733c47` | Two-photo scheduled request retained `Seed bold`, bold `5:4` and the date scheduling enum. No callback occurred before choosing the date. |
| `025420` / `c609b7d7` | Final production UI: normal send, Retry all retaining the attributed caption, When Online with two mapped photos, Retry remaining returning just the second photo with empty caption/entities, and dark three-line keyboard/send. Retry safe-area top stayed 64 pt and the grid no longer had the extra gap. |
| `025645` / `cbc81ba9` | Only the transition probe changed from the preceding build. Entity/ownership and transition probes passed. Fresh Gallery send/import/reopen preserved bold `5:4`, with no extra inset; an outside tap after recovery showed Cancel selection. Contact regression returned one comment before one card, correct reply flags and visible multiline input above the keyboard. |

The entity probe covers immutable caption/entity snapshots, changed and retyped drafts, translating
revision ownership between VMs, and excluding an accepted prefix from retry. Existing formatting,
UTF-16, marked-text and undo checks also passed. This is deterministic state proof, not a real send.

Local evidence is under `/tmp/bettertg-gallery-audit/`: request reports, layout measurements,
`retry-chrome-fixed.png`, `partial-final.png`, `dark-keyboard-final.png`, `last-build-retry.png`,
`contact-regression.png`, and final probe reports. These files are non-durable. The bounded final
Simulator log read found no Auto Layout conflict, presentation warning or terminating exception.
Normal relaunch returned to phone entry.

The UI pass reproduced an extra navigation-bar-sized gap above the grid after retry: the screen's
safe-area top changed from 64 to 128 pt. An offset clamp did not fix it and was removed. The dismissed
navigation container must release its chrome and reserved inset before Gallery enters a new container.
Gallery also removes the old presentation's outside-tap recognizer so the new container gets one.
The transition probe now checks that a retained screen can enter another navigation controller without
accumulating insets. Its first version re-presented immediately after a nonanimated dismiss and failed;
the final version awaits UIKit's dismissal and presentation completions, matching the production path.
It passed without weakening its inset assertion. An early CLI action also read a menu during its closing
animation; fresh snapshots and explicit fixture-result waits resolved the transient selector errors.

## Limits and next

The DEBUG fixture intercepts sends. It exercises the real Gallery, panel, schedule picker and Photos
loader; it does not prove TDLib acceptance, server delivery, network retry, partial album responses or
an actual client-renewal event. Those paths have source review and deterministic ownership checks only.
Custom emoji, IME composition, media edits, video/Live Photo import, physical-device behavior and
process-death recovery were not revalidated here. Existing slow-mode scheduling remains open.

Next: validate the Gallery send/error/client-renewal path on a dedicated authorized account, then the
remaining File attachment comment and prior menu/Stories/device gaps. No messages were sent to Telegram.
