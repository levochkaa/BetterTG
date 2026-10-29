# Chat-list header panels — 2026-10-29

Scope: the remaining list voice/live-location chrome from `goal.md`, from `acbaddab` on
`t3/refresh-goal-prompt`. Implementation is in this audit's commit.

## Reference and change

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:

- `submodules/TelegramUI/Components/HeaderPanelContainerComponent/Sources/HeaderPanelContainerComponent.swift`:
  one interactive glass surface, 16 pt side insets, 20 pt corners, media before location, and a separator between rows.
- `submodules/TelegramUI/Components/MediaPlaybackHeaderPanelComponent/Sources/MediaNavigationAccessoryHeaderNode.swift`:
  40 pt row, centred 12/10 pt title/subtitle, rate-dependent text width and a 2 pt progress line.
- `submodules/TelegramUI/Components/LiveLocationHeaderPanelComponent/Sources/LiveLocationHeaderPanelComponent.swift`
  and `submodules/ChatListUI/Sources/ChatListControllerNode.swift`: 40 pt location row and shared panel composition.

Before: two full-width `systemChromeMaterial` strips with 37 pt rows; the media title was centred in the space
left of the rate button, and hiding that button still reserved its width. The old strip was reproduced using an
existing voice message in Saved Messages (`/tmp/bettertg-panels-voice-before.png`).

After: `TelegramHeaderPanelsView` hosts both real row views inside interactive glass. The list extends one
`TelegramBarBackgroundView` from the status area through the panels, with the user's 10 pt bottom gap.
The existing list inset adjustment preserves the viewport when rows appear, disappear or hide for search.
Both shared row types use 40 pt height; the voice title and subtitle stay centred and reclaim width without rate.
The explicit accessibility order also removes the hidden rate button. Playback, account filtering and live-location
server actions remain in their existing owners. The chat's existing shared backdrop receives the 40 pt row geometry;
this change does not port a new glass container to chat banners.

## Fixture evidence

iPhone 17 Pro Simulator, iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`.
The account-free `-ui-probe-header-panels` uses the production container and row views, with local action handlers.
It does not start media, change the saved playback rate, request GPS or send a location.

On build `11542a79e6de79e547a49488a1e3e61c5df60f6314207ee48e539ec5c572dda3` (debug dylib SHA-256;
installed product matched):

- Dark and light: two 40 pt rows at x=16, width=370 on a 402 pt screen; total accessory inset 90 pt.
- Location alone: 50 pt inset, two reachable controls. Hidden: zero inset, no row controls in accessibility or hit-test.
- Both: six controls whose centre hits remain descendants of the interactive glass's content view.
- Play/pause, rate, media open and location open reached their handlers. Music swipe right reached next.
- Location close opened the production confirmation sheet; its fixture stop handler removed the location row.
- Collapse interrupted at 0.04 s and again at 0.08 s settled with both rows restored, without a stranded overlay.
- A held Play button visibly expanded/brightened the common glass, then returned on release. The 30 fps recording
  checks the response and interruption frames, not physical-device timing.
- Launch console had zero Auto Layout conflict reports and zero fatal errors.

Evidence: `/tmp/bettertg-panels-both-dark.png`, `bettertg-panels-both-light.png`, `bettertg-panels-stop-fixture.png`,
`bettertg-panels-music.png`, `bettertg-panels-interaction.mp4`, `bettertg-panels-hold-frames.jpg`,
`bettertg-panels-interrupt-frames.jpg`. The fixture exposed the hidden rate button in the explicit accessibility
array; that finding was fixed after these captures.

## Final build and app flow

SwiftFormat covered all seven changed Swift files. `./build.sh build` succeeded without warnings or errors;
complete log: `build-Debug-20261029-233519-84640-13709.log` (146 s). The final installed debug dylib matched
SHA-256 `1d673f118da42851fc3094980c3a64fa74cddcfff513f04dced5302b1863fe29`.

- The fixture's final build showed five reachable controls with music plus location; the hidden speed button was
  absent from the accessibility tree. The preceding six-control voice state also passed.
- Normal launch, existing Saved Messages voice: Play and Pause worked in chat; returning to the list showed a 40 pt
  glass row and 50 pt accessory inset. The first row moved from y=166 to y=216 on this screen.
- Focusing search removed the panel and its accessible controls while showing the keyboard. Closing search restored
  the panel and the same first-row position. No search text was entered.
- Tapping the panel title opened Saved Messages with the voice message visible. Its shared chat row also measured 40 pt.
- After returning, Play resumed and advanced the progress line in the list. A point tap on Close removed the panel,
  returned the first row to y=166 and left the list on screen. Playback was stopped at the end; no draft, send or
  persisted preference changed.

Evidence: `/tmp/bettertg-panels-voice-after.png`, `bettertg-panels-search-hidden.png`,
`bettertg-panels-open-message.png`, `bettertg-panels-root-resumed.png`, `bettertg-panels-close-point.png`,
`bettertg-panels-close-point.mp4`. The close recording has one tap at (364, 186).

Automation caveat: two earlier `press @ref` Close calls removed the panel and then opened the Saved Messages row
which moved underneath it. A settled point tap at the same location did not reproduce that navigation. This is
not proven to be an app defect or a tool retry; no speculative production fix was made. Keep the ref-path anomaly
separate from the recorded point-tap result.

## Limits

The fixture does not prove TDLib live-location updates, opening a received location or stopping a server broadcast.
Multi-account transitions, iPad/rotation, large accessibility sizes, RTL, iOS 27 and physical-device timing were not
exercised in this slice. Remaining chrome: Web App header/fullscreen, login bar, invite-link sheet, link spinner,
network usage segmented control, contact send bar and sticker-settings toolbar.
