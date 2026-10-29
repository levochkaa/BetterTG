# Network-usage segments and navigation hit testing — 2026-10-30

Scope: the network-usage segmented-control UI pass, from `653a0a4a` on
`t3/refresh-goal-prompt`. Implementation is in this audit's commit.

## Reference and changes

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`, read with `git show`:

- `submodules/TelegramUI/Components/SegmentControlComponent/Sources/SegmentControlComponent.swift`:
  the iOS 26 native `UISegmentedControl`, 36 pt height, 14 pt semibold labels and guarded chrome adaptation.
- `submodules/TelegramUI/Components/StorageUsageScreen/Sources/DataUsageScreen.swift`:
  All / Mobile / Wifi, initially All, and the matching usage-since text.
- `DefaultDayPresentationTheme.swift` and `DefaultDarkPresentationTheme.swift`:
  segmented background/foreground/text colours.

`TelegramSegmentedControl` preserves UIKit's live selection lens and continuous gestures. Its wrapper
centres the 36 pt control in BetterTG's 44 pt navigation title slot. The guarded native hierarchy changes
match Telegram: hide immediate image chrome and tint plain backing views inside the selector loupe.
Light/dark changes refresh the colours. The existing two-mode statistics filter becomes three modes;
All combines mobile and Wi-Fi, with roaming/other classification and no-network exclusion preserved.
The six new Telegram localization keys have English fallbacks. Data loading, category mapping and the
confirmed TDLib reset operation are unchanged.

Two runtime defects were reproduced and fixed:

1. Dragging Mobile toward Wifi began BetterTG's full-screen swipe-back. The navigation gesture now excludes
   touches inside `UISegmentedControl`, as it already excludes sliders and the voice-trim editor. UIKit owns
   segment selection; a swipe outside the control still navigates back.
2. After scrolling, Back and segments remained visible but stopped receiving taps. Temporary hit-test logging
   showed `_UITableViewHeaderFooterContentView` at both button positions; table section headers had been
   inserted after the custom bar. `layer.zPosition` affected drawing only. The common chrome's layout now calls
   `bringSubviewToFront`, keeping UIView hit-test order aligned with its visible order. At the same offset,
   hit tests then returned `UIButton` and `Control`, both inside the bar. The diagnostic timer was removed
   before the final build. This fixes the shared overlay mechanism; runtime coverage below is not an audit of
   every consumer.

An initial table touch-cancellation hypothesis was discarded after recorded frames showed the swipe-back
transition. Its temporary table subclass is absent from the final code.

## Verification

SwiftFormat covered all six changed Swift files. Final `./build.sh build` passed in 23 s; complete log
`build-Debug-20261030-005956-88318-26204.log` contains zero warnings/errors. Installed and built debug dylibs
matched SHA-256 `1d6d03f6d7220255310af4b3d68a3a1b8a8f52497404ef0962573d4e098b93be`.
`plutil -lint` passed for Telegram.strings, and `git diff --check` passed.

iPhone 17 Pro Simulator / iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`, driven in the T3 Device panel:

- New `-ui-probe-network-usage` seeds the real controller with local entries and blocks both reads and resets
  from reaching TDLib. On the final build at `2026-10-29T21:00:36Z`, its verifier passed initial All, repeated
  All/Mobile/Wifi selection, roaming/other classification, no-network exclusion, photo aggregation and totals:
  All 1600/2000 bytes, Mobile 400/600, Wifi 1200/1400. This verifies UI filtering and rows, not server counters.
- Final-build fixture smoke: scroll, tap Mobile, drag right to Wifi, inspect updated totals/footer, then Back
  to the fixture host. No unintended pop or stuck control. The captured launch console has no Auto Layout
  conflicts or fatal/precondition failures; it does not cover all subsequent gestures.
- Identical production code in the preceding diagnostic build checked light/dark, Back after scrolling,
  visible Mobile/Wifi totals and footer, and successful swipe-back from outside the control. Its installed hash
  was `b2df8c918f14f8dc86c8a3e30f5b44f6b1b810ea1420cc1423c37cd19a02622b`, warning-free build log
  `build-Debug-20261030-005824-86725-30746.log`. Only diagnostic logging was subsequently removed.
- Earlier segment code with the same gesture fix was recorded during hold, forward/reverse drag and release
  outside. Frame inspection shows the native lens moving and settling, rather than the screen moving back.
  The then-unfixed scrolled-header tap failures were reproduced, not counted as passing evidence.
  The fixture's Reset confirmation was opened and cancelled; real statistics were never reset.
- Final-build real flow, without launch flags: Chats → Settings → Data and Storage → Data Usage loaded TDLib
  statistics, initially All. After scrolling, Mobile showed zero usage on this Simulator, and dragging to
  Wifi showed 216.2 MB sent / 1.71 GB received with the corresponding footer. Back returned to Data and Storage.
  Scrolling that second settings screen and tapping Back returned to Settings; another Back returned to Chats.
  No account, draft, preference or statistics mutation was performed. Normal launch restored persisted appearance.

Evidence under `/tmp/`: `bettertg-network-hit-before.txt`, `bettertg-network-hit-after.txt`,
`bettertg-network-before-drag-frames.jpg`, `bettertg-network-corrected-drag-frames.jpg`,
`bettertg-network-segments.mp4`, `bettertg-network-final.mp4`, `bettertg-network-light.png`,
`bettertg-network-hit-after-mobile.png`, `bettertg-network-hit-after-wifi.png`,
`bettertg-network-release-scrolled.png`, `bettertg-network-real-all.png`,
`bettertg-network-real-mobile.png`, `bettertg-network-real-wifi.png`,
`bettertg-data-storage-scrolled.png`, `bettertg-network-release-console.log`.

Tool corrections during the final pass: `--launch-arg` was rejected and corrected to documented
`--launch-args`; `--resize` was rejected and replaced with `--pixel-density 1`; a bare `e5` was rejected
and retried with a fresh `@e5`. All corrected calls succeeded. No alternate device driver was used.

## Limits and next

This slice preserves BetterTG's grouped statistics rows. Telegram's pie chart, expandable categories and
collapsing large header are not implemented here. The native subview adaptation is guarded but depends on
UIKit hierarchy, as the reference does; iOS 27, iPad, rotation, RTL, Dynamic Type and physical-device behavior
remain unverified. VoiceOver gestures and real network-statistics reset were not exercised. Numeric fixture
proof and Simulator reads do not prove cellular metering on a physical device.

Next UI pass: contact-selection send bar, then sticker-settings toolbar. Invite pull-down/progress morph,
menu/readiness, Stories and prior physical-device gaps remain open.
