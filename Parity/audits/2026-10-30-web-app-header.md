# Web App header — 2026-10-30

Scope: ordinary Web App chrome and its fullscreen handoff from `goal.md`, from `89b4b26e` on
`t3/refresh-goal-prompt`. Implementation is in this audit's commit.

## Reference and change

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:

- `submodules/WebUI/Sources/WebAppController.swift`: ordinary navigation controls, Back/Close, More,
  app-provided header colours, page viewport below the navigation bar and fullscreen layout.
- `submodules/WebUI/Sources/WebAppTitleView.swift`: centred 17 pt semibold title and 13 pt mini-app subtitle.
- `submodules/WebUI/Sources/FullscreenControlsComponent.swift`: **blur**, 30 pt controls, 16 pt sides and
  8 pt below the status area. This component still uses `BlurredBackgroundView`, not Liquid Glass.

Before: a solid 56 pt header, plain Back/Close, circled ellipsis and no subtitle. The existing local Web App
fixture reproduced it. After: `WebAppHeaderView` uses the common `TelegramBarBackgroundView` and two
44 pt interactive glass groups, with 16 pt sides and 10 pt above/below the buttons. Explicit header colours
retain their solid background and contrasting content without changing the page's theme.

The Back icon and label are live views inside the glass. A custom noninteractive stack inside the button avoids
the label's separate release movement observed with `UIButton.Configuration`; constraints pin the button to
the glass content view. The title remains centred between symmetric bounds and truncates when space is limited.

The page keeps Telegram's viewport below the header. Removing WebKit's outer clipping allows scrolled content
to draw through the light bar background; the containing content view clips at the sheet's bounds. Fullscreen
controls, bridge actions, closing confirmation and ownership remain in their existing implementation. No new
minimize support is claimed. The fixture now applies the safe-area events it already receives, so its own
buttons stay below the fullscreen controls.

## Final build and Simulator proof

SwiftFormat covered all three changed Swift files. `./build.sh build` passed; the complete log contains zero
warnings and errors: `build-Debug-20261029-235722-82978-22601.log` (32 s).
Installed and built debug dylibs matched SHA-256
`e33b1f11c2ef961e5780bf2c53c06fe82bd0d01dc1499ec40015b5b6457bcea1`.

The existing `-ui-probe-web-app` ran on iPhone 17 Pro Simulator / iOS 26.5,
`8108A92F-7E93-49C8-87F4-FA53A5A40A99`. It uses local HTML and bot ID 0; no real bot was contacted by these actions.

- Normal sheet: Close and More measured 44 pt at x=16/342 on the 402 pt screen; centred title/subtitle.
- Back: holding the native button expanded/brightened its glass; the final recording shows icon and label
  staying together on release. The page received `back_button_pressed`.
- Scroll: page buttons drew beneath the light header; the controls and title stayed fixed.
- Medium sheet: dragging the grabber retained the header and reachable controls. Entering fullscreen from
  that detent produced an 874 pt viewport, safe top 54 and content-safe top 46.
- Fullscreen Close opened the existing confirmation; Cancel retained the page. Exit restored one ordinary
  header, the 748 pt viewport and zero top safe/content-safe insets.
- Explicit white header: black title/buttons on solid white while the page stayed dark. More included Settings
  after the fixture enabled it; selecting it delivered `settings_button_pressed` and dismissed the menu.
- Enter → exit at 40 ms → enter at 80 ms settled fullscreen with one Close and one More, an 874 pt viewport and
  54/46 pt top insets. The page recorded `fullscreen_changed` true/false/true. These are requested JS delays,
  not measured frame timing.
- Final native Close → Close Anyway dismissed the fixture; no WebView or Probe Bot remained in accessibility.
  No messages, location, permissions, account settings or persistent Web App storage were changed.

Final evidence under `/tmp/`: `bettertg-webapp-final-back.mp4`, `bettertg-webapp-final-back-frames.jpg`,
`bettertg-webapp-scroll-under.png`, `bettertg-webapp-compact.png`, `bettertg-webapp-fullscreen-safe.png`,
`bettertg-webapp-final-exit.png`, `bettertg-webapp-final-light.png`, `bettertg-webapp-final-interrupted.png`.
Earlier red-header and menu captures were from the intermediate build and are not final-build proof.

## Limits and next

This is local bridge/UI proof, not real-bot/server parity. Minimized Web Apps, verified-bot metadata, long/RTL
titles, large accessibility sizes, keyboard/rotation, iPad, iOS 27 and physical-device behaviour were not validated.
Fullscreen colours still follow the existing header-colour/status-style policy; that policy was not changed.
Remaining chrome: login bar, invite-link sheet, link spinner, network usage segmented control, contact send bar
and sticker-settings toolbar. Other goal gaps and device/account-dependent checks remain open.
