# Invite preview chrome — 2026-10-30

Scope: the invite-link preview entry in the UI pass, from `f5e4abb1` on
`t3/refresh-goal-prompt`. Implementation is in this audit's commit. Link-resolution progress is separate.

## Reference and change

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:

- `submodules/JoinLinkPreviewUI/Sources/JoinLinkPreviewControllerNode.swift`: light/dark blur, 80% theme
  tint, 16 pt corners, a 30 pt close image in a 44 pt target, slide and dimmer transitions.
- `submodules/JoinLinkPreviewUI/Sources/JoinLinkPreviewPeerContentNode.swift`: 100 pt avatar, solid
  52 pt Join button with 11 pt corners and 16 pt sides; the approval explanation follows the button.
- `submodules/Display/Source/LayoutSizes.swift`: sheet width capped at 440 pt compact / 414 pt regular.

BetterTG previously used an opaque inset card, a separated 57 pt Join row and a second Cancel card.
The preview now has the reference blur/tint through the bottom edge, a close button pinned to its top,
and a solid Join action. The content ends 10 pt above the bottom safe area. Existing full descriptions
remain scrollable when they exceed the available height. The close button stays outside that scroll.

A custom UIKit modal animator owns slide and dimmer together in both directions. Previously the sheet
slid only after UIKit's crossfade completed in `viewDidAppear`. Modal accessibility scope and Escape
handling were added. The button now replaces its title with UIKit's central progress indicator while busy.

Invite checking/routing, account authority, member reads, join request/results, error alerts and request-sent
toast are unchanged. No invite was created, exported, joined or requested during validation.

## Verification

SwiftFormat covered all three changed Swift files. Final `./build.sh build` passed in 22 s; complete log
`build-Debug-20261030-003408-55727-15449.log` contains zero warnings and errors. Installed and built debug
dylibs matched SHA-256 `9b508fcf08a868eef8295aaa8867d3ba44e7f6ae8a287fe2247c9e426f79d2e4`.

iPhone 17 Pro Simulator, iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`:

- `-ui-probe-invite-preview` presents the real controller with local metadata, no photo/member IDs,
  and a replaced Join target before display. That target only exercises the real busy state for three seconds.
- Final build: dark group preview, light request preview, approval explanation below the 52 pt button,
  close and outside-tap dismissal. The fixture's appearance override is passed explicitly to the preview;
  no persistent appearance preference changes.
- A long description reaches Join by scrolling. Close stays fixed. During the local busy state a close tap
  leaves the preview open; after completion the same tap dismisses it. Normal app launch was restored.
- Final launch console contains zero Auto Layout conflicts and fatal/precondition failures. This is launch
  capture, not a console trace covering every later interaction.

Final captures: `/tmp/bettertg-invite-final-group.png`, `bettertg-invite-final-request-light.png`,
`bettertg-invite-final-long-top.png`, `bettertg-invite-final-long-bottom.png`,
`bettertg-invite-final-busy-blocked-close.png`, `bettertg-invite-final-dismissed.png`.

The earlier warning-free build (`build-Debug-20261030-003012-49981-694.log`, dylib
`b93b8ccb88dcb494c12a675aa2540bda31700e2da3b61aa64bed54a2f9caa168`) contains identical production code.
Its recorded presentation/dismissal was inspected in reduced frames: the sheet and dimmer move together,
without the old completed crossfade preceding the slide. Evidence: `/tmp/bettertg-invite-transitions.mp4`,
`bettertg-invite-present-frames.jpg`, `bettertg-invite-dismiss-frames.jpg`.

Two input commands were rejected before dispatch: a stale accessibility ref after changing the fixture's
appearance, and a fractional duration where the pan command expects integer milliseconds. A fresh snapshot
and the documented `500` ms duration respectively resolved them on the first retry.

## Remaining limits

This closes the old card/Cancel chrome gap, not the complete invite flow. Telegram's pull-down dismissal
and SolidRoundedButton's full-size ring morph are still missing; BetterTG uses a disabled solid button with
an embedded native spinner. Telegram truncates descriptions to eight lines (three in landscape), while this
slice retains BetterTG's full scrolling text. Member/photo loading, readiness, real join results, VoiceOver
Escape, RTL, Dynamic Type, rotation, iPad, iOS 27 and physical devices were not exercised here.

Continue with link-resolution spinner, then network segmented control, contact send bar and sticker-settings
toolbar. Track the invite interaction limits above separately; do not count this chrome audit as full parity.
