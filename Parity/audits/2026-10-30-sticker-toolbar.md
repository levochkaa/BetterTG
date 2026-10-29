# Sticker-settings selection toolbar — 2026-10-30

Scope: InstalledStickerSetsViewController's Sticker and Emoji editing toolbar, from `1d235130`
on `t3/refresh-goal-prompt`. Implementation is in this audit's commit.

## Reference and changes

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`, read with `git show`:

- `submodules/SettingsUI/Sources/Stickers/InstalledStickerPacksController.swift`: StickersToolbarItem
  supplies Delete / Archive / Share, disabled with no selection, and mode-specific confirmations.
- `submodules/ItemListUI/Sources/ItemListControllerNode.swift`: the active implementation uses a 44 pt
  GlassControlPanelComponent with three separate capsules. Its old ToolbarNode block is commented out.
- `submodules/TelegramUI/Components/GlassControls/Sources/GlassControlGroup.swift` and
  `GlassControlPanel.swift`: medium 17 pt text, panel foreground, half-opacity disabled content,
  interactive enabled glass, and a centre action that yields space to its neighbours.
- `DefaultDayPresentationTheme.swift` / `DefaultDarkPresentationTheme.swift`: panel controls are black/white.

BetterTG's system UIToolbar already drew separate capsules on iOS 26. This slice replaces it with
StickerSelectionToolbar to use the common TelegramBarBackgroundView across the full width and safe
area, plus TelegramGlassPlatter buttons with live content inside glass. The chosen BetterTG geometry
is retained: 16 pt side margins, at least 12 pt between capsules, and 10 pt below the 44 pt row.
Text padding is 12 pt per side. Buttons fill their capsules, including padding. Preferred widths can
shrink for long localized titles; minimum width is 44 pt and labels truncate rather than conflict.

The controller reserves 54 pt above the existing bottom safe area. Since its root is a UITableView,
the toolbar follows the viewport bounds and stays above section headers in UIView hit-test order.
Done removes the reservation; fading controls immediately stop accepting touches. Existing ordered
selection, reorder requests, deferred reload, confirmations and TDLib removal paths are preserved.
Delete/Archive popovers now anchor to their own buttons; Share uses the source capsule's rectangle
before editing ends, instead of the new Edit button in the navigation bar.

## Verification

SwiftFormat covered both changed Swift files together. Final `./build.sh build` passed in 19 s;
complete log `build-Debug-20261030-013544-33846-11879.log` contains zero warnings/errors.
Installed and built debug dylibs matched SHA-256
`3030016f55bf677bffefe0edfe108d1ff9f35a45e407c2c6f053065a16aef4ca`.
`git diff --check` passed.

iPhone 17 Pro Simulator / iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`, T3 Device panel:

- Final normal route: Settings → Appearance → Stickers and Emoji → Edit. Empty-selection actions
  are disabled. Capsule/button frames are Delete `(16,786,73,44)`, Archive `(160.67,786,81,44)` and
  Share `(318,786,68,44)`. The row ends at 830, leaving 10 pt before the 840 pt safe-area edge.
- Final build: select one set; tap Delete at x=21 and Archive at x=166, inside their leading padding.
  Both open the one-set confirmation at the corresponding source. Dismissal outside preserves selection.
  Tap Share at x=381, inside trailing padding: the system activity sheet opens and editing ends.
  It was dismissed without choosing an activity. No pack was changed or shared.
- Before the final padding/width refinement, the same controller integration checked selecting two sets,
  the two-set Archive confirmation, deselection, Share dismissal, six rapid Edit/Done taps, and scroll.
  Toolbar y remained 786; final state had one disabled toolbar, and Done removed it. Emoji mode checked
  its disabled toolbar, selecting one pack and `delete 1 emoji pack`, then cancellation. That installed
  build's hash was `618b6dda711c114f6c3c7d6f88858ae8b37a364c4e98c1d2dbd0a2790d061638`,
  warning-free log `build-Debug-20261030-012647-22900-17940.log`.
- The preceding build also exercised hold, movement and release outside. Reduced recording frames show
  glass swelling/brightening and returning, plus toolbar fades during rapid editing changes. The recording
  was stopped and inspected; it is 30 fps and does not prove precise gesture timing or 120 Hz behavior.
- A bounded Simulator log read found no recorded Auto Layout conflicts or fatal/precondition failures
  during that pass. Final screenshots were inspected as reduced copies. Normal launch restored Chats.

One launch with console capture left the installed-set screen empty; reopening it did not populate it.
An ordinary relaunch loaded it, and the final build's ordinary launch also loaded it. The cause is
unconfirmed; this is not counted as a loading fix. One automation call failed with
`Ref @e46 had no confirmed resting position when the transition window ran out`; a fresh snapshot
and one retry succeeded. No alternate device driver was used.

Evidence under `/tmp/`: `bettertg-sticker-toolbar-before.png`, `bettertg-sticker-toolbar-empty.png`,
`bettertg-sticker-toolbar-selected.png`, `bettertg-sticker-toolbar-scrolled.png`,
`bettertg-sticker-toolbar.mp4`, `bettertg-sticker-hold-frames.jpg`, `bettertg-sticker-release-frames.jpg`,
`bettertg-sticker-rapid-frames.jpg`, `bettertg-sticker-bulk.json`, `bettertg-emoji-delete.json`,
`bettertg-sticker-final-empty.json`, `bettertg-sticker-final-selected.png`,
`bettertg-sticker-final-delete-edge.json`, `bettertg-sticker-final-archive-edge.json`,
`bettertg-sticker-final-share.json`. These are local verification artifacts, not durable fixtures.

## Limits and next

No actual delete, archive, reorder, share activity, preference or account mutation was performed.
Light mode, long translations, RTL, Dynamic Type, VoiceOver, iPad, rotation, iOS 27 and physical devices
remain unverified. This does not change Telegram's pack-management backend or establish full parity.

Next: common attachment comment input and silent/scheduled contact sending. The intermittent empty
installed-set load, prior invite/menu/readiness/Stories gaps and physical-device checks remain open.
