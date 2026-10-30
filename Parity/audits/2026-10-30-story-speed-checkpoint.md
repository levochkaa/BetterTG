# Story playback speed: source checkpoint — 2026-10-30

Status: reviewed, implementation pending. Base `c83affe3` on `t3/refresh-goal-prompt`.
The user requested the nearest checkpoint before implementation began. No application code changed
in this slice. The preceding channel-interactions implementation and its proof remain in
[the channel audit](2026-10-30-channel-story-viewers.md). Full parity remains open.

## Confirmed gap

Official Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:

- `submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerComponent.swift`,
  `contextMenuSpeedItems`: Back, a slider from 0.2 to 2.5, a separator and 0.5/1/1.5/2 presets.
  Slider changes update the visible video and shared story rate immediately, rounded to tenths;
  finishing updates the parent menu's rate value. Dragging leaves the menu open; a preset dismisses it.
  Preset checkmarks clear after slider changes. The parent row shows the current rate below its title
  and in its gauge icon. Own, channel-admin and other-story menus share this behavior.
- `submodules/TelegramUI/Components/SliderContextItem/Sources/SliderContextItem.swift`: a 45 pt custom
  row with 10 pt side insets and monospaced 17 pt digits. Its white fill clips black foreground text
  over secondary background text. Under 40 pt wide the fill shrinks vertically and rounds with its
  width. Pans add horizontal translation divided by the entire row width times the range; taps map
  their horizontal position to that range. The row cannot be highlighted or selected as an action.

The inspected checkout differs from that upstream component only by an unrelated Swiftgram import;
the slider file matches upstream. No live Telegram UI comparison was performed.

BetterTG currently creates only the four preset child actions in
`StoryViewerController.presentMoreMenu`. `setBaseRate` updates the viewer and `LocalMediaPlayer`;
`startVideo` reapplies the viewer rate for the next video. There is no slider/custom-row support in
`TelegramContextMenuAction`, and the speed row lacks Telegram's second-line value and live icon updates.

The missing range also reaches playback: `LocalMediaPlayer.setRate` clamps to 0.5–2. A slider alone
would show 0.2 or 2.5 while playing at a different rate. Its two external-rate synchronization methods
and `TDLibVODFFmpegSampleBufferPlayer.setRate` also clamp to 0.5–2, so inspect all rate entry points
and consumers before extending the shared player contract.

## Resume implementation

1. Add a UIKit custom slider row to the existing menu/submenu structure. Keep the current stacked
   submenu animation and parent navigation. Preserve the slider's geometry, value mapping, live updates
   and nonselectable behavior; do not substitute a separate sheet or more preset rows.
2. Make touch ownership explicit. `ContextMenuTouchRecognizer` observes touches simultaneously without
   cancelling them, while `touchOrigin` currently treats the entire menu as action space. A touch that
   begins in the slider must stay with the slider through release/cancellation and must not trigger an
   adjacent action or menu dismissal. Review the initiating-finger handoff and pending auto-navigation.
3. Bind the parent rate text/icon and preset checkmarks to the current value; reopen the submenu with
   that value. Keep changes when returning to the parent or dismissing. Preserve the viewer's pause
   while the menu is open and apply the rate to subsequent videos.
4. Support the actual 0.2–2.5 playback range without changing existing callers' intended bounds.
   Check local and streamed playback, buffering/preroll, pause/resume and external playback control.
5. Extend meaningful playback/menu probes and inspect real tap/drag/release/cancel behavior. Existing
   `StoryViewerProbe` only checks speed-item/title construction; `menu-video` only checks the top-level
   menu order. Neither proves slider tracking or the actual player rate. Include a preset regression,
   Back/reopen, boundary rates, accessibility adjustment and next-video retention.

## Verification and handoff

`./build.sh build --simulator-id 6DF66290-FE39-475C-91FA-0267B1718DDA` passed in 29 s on Xcode 27.1.
The complete 1,076-line `.build/logs/xcodebuild/build-Debug-20261030-153750-13866-11418.log`
contains `BUILD SUCCEEDED` and no warnings or errors. No Swift edits required formatting.
No app was installed, launched or driven in this source-only slice. The previous device CLI failures
and incomplete final manual repeat remain recorded in the channel audit; they were not reclassified
as a pass. Resume device work through the required Device panel workflow and fresh complete snapshots.

The next implementation starts from this checkpoint; no partial slider implementation needs recovery.
