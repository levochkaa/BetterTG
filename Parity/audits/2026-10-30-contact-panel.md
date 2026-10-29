# Contact selection and the shared attachment panel — 2026-10-30

Scope: the contact-selection send bar, from `490041b0` on `t3/refresh-goal-prompt`.
Implementation is in this audit's commit.

## Reference and changes

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`, read with `git show`:

- `submodules/TelegramUI/Sources/ContactSelectionController.swift`: ContactsPickerContext publishes
  selection count and forwards send to requestMultipleAction. The old ContactSelectionCountPanelNode
  remains defined upstream but is not the current attachment controller's laid-out send panel.
- `submodules/AttachmentUI/Sources/AttachmentController.swift`: selection drives the common panel.
- `submodules/AttachmentUI/Sources/AttachmentPanel.swift`: tabs give way to the input/send row;
  the selected tab scrolls into view with 35 pt of surrounding space.

ContactSelectionViewController now adopts AttachmentPanelContent. Its ordered selection updates the
existing AttachmentPanelView, replacing tabs with its count and Send instead of adding a second count
bar and changing insets. It keeps single-contact, multi-contact and extended-vCard routing and the
existing single-finish guard. The shared panel disables outgoing controls and hides them from
accessibility immediately, so fading controls cannot send or switch tabs.

The contact table ends at the keyboard layout guide; with the keyboard absent it fills the screen
under the panel (`usesBottomSafeArea = false`). Search results stay above the keyboard.

A reproduced overflow defect is also fixed: every tab replacement creates a new strip, whose zero
offset clipped selected Contact to about 6 pt. After real layout, the strip reveals the selected tab
with Telegram's 35 pt margin. Ordinary user scrolling is preserved; width changes reveal it again.

## Verification

SwiftFormat covered all four changed Swift files in one invocation. Final `./build.sh build` passed
in 35 s; complete log `build-Debug-20261030-011841-14320-30693.log` has zero warnings/errors.
Installed and built debug dylibs matched SHA-256
`74d8aca19264ce813f3969536c37d2a4c64972b0afbcf96b405fc7941b23be5e`.
`git diff --check` passed.

iPhone 17 Pro Simulator / iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`, driven in the T3 Device panel:

- New `-ui-probe-contact-panel` uses the real picker with 24 local contacts and an intercepted send.
  It performs no phonebook reads or message sends. Final fixture opens Gallery, then Contact through
  the production replacement route. Medium/large detents show the selected overflowing Contact tab.
  Selecting Ada 01 and Ada 02 and double-tapping Send yields exactly
  `sends=1; dismissals=1; names=Ada 01,Ada 02`.
- Final fixture Contact → File → Contact retains panel frame `(0, 364, 402, 100)` in the medium sheet,
  with Contact fully visible and selected again. The appropriate top inset changes with search content;
  the bottom inset stays 100 pt. Screenshots were viewed as reduced copies.
- Final `-ui-probe-attachment-transition` result, freshly written at `2026-10-29T21:22:39Z`, passed live
  screens/chrome during fade, latest-tab wins, restored alpha/insets/appearance, dismissal cancelling a
  pending tab, and switching during presentation.
- Final normal launch: Saved Messages → Gallery → Contact. Selected Contact is fully visible
  (57.61 pt wide at the sheet's scale, previously 5.76 pt); tab y remains 777.66 before/after.
  No real contact was selected. Cancel and normal launch restored Chats.
- The first build of the same contact integration, before the tab-reveal fix, checked light/dark,
  tabs ↔ Send, count 1 → 2, release outside Send without sending, deselect-to-zero, search with keyboard,
  ordered search selection (`Cora 01,Ada 02`), double Send firing once, Cancel, six rapid toggles, and
  single-contact send. That build's dylib hash was
  `983a8dd5ccb4e1a6972440caae32984d9ef93d51c2a48291191c1626bda6fb8a`;
  warning-free log `build-Debug-20261030-010950-2856-21230.log`. Its recording was stopped and its
  reduced selection frames inspected: the row stays in place while tabs fade and the count updates.

An initial fixture presented Contact directly at the large detent and showed a 16 pt safe-area change
on first interaction. The real Gallery → Contact route retained its geometry. The fixture was changed
to match that route; no compensating production safe-area adjustment was added. This is not counted
as a fixed production defect. One covered parent Cancel reference failed with
`Ref @e4 has no parent-owned touch point outside its interactive descendants`; the suggested child
reference succeeded after a fresh snapshot.

Evidence under `/tmp/`: `bettertg-contact-panel.mp4`, `bettertg-contact-panel.gesture-telemetry.json`,
`bettertg-contact-panel-select-frames.jpg`, `bettertg-contact-panel-search.png`,
`bettertg-contact-panel-light-selected.png`, `bettertg-contact-final-medium.png`,
`bettertg-contact-final-selected.png`, `bettertg-contact-final-roundtrip.png`,
`bettertg-final-contact-selection-layout.txt`, `bettertg-final-contact-selection-panel-probe.txt`,
`bettertg-contact-attachment-transition.txt`, `bettertg-contact-real-final.json`,
`bettertg-contact-real-final.png`. These local artifacts are not durable repository fixtures.

## Limits and next

This reuses BetterTG's existing shared send row. Telegram's editable comment input and silent/scheduled
contact sending are still absent; this is not full attachment input-panel parity. No real contact send,
extended-vCard field selection, permission change, VoiceOver gestures, iPad, rotation, RTL, Dynamic Type,
iOS 27 or physical device was exercised. No account, draft, phonebook or preference was changed.

Next: sticker-settings toolbar and the remaining common attachment input/send options. Prior invite,
menu/readiness, Stories and physical-device gaps remain open.
