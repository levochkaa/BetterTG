# Context-menu gestures — 2026-10-12

Source: `/Users/lev/Developer/CustomContextMenu` (UIKitCore iOS 27.0 24A434): `App/MenuMotion.swift`,
`App/MenuTouchRecognizer.swift`, `App/CustomMenu.swift`, `App/NativeUIKit.swift`, `Tests/InteractionChecks.swift`,
`Research/Interaction/README.md`. Constants are taken from the source, none tuned by eye.

| Area | Port | BetterTG adaptation |
| --- | --- | --- |
| Motion model | `ContextMenuMotion`, `ContextMenuSpring`, `ContextMenuTouchSession` verbatim: press progress and scale, radial rubber band 15 / 0.2, preview offset clamped toward the menu, closed-form spring, release rules | `platterOffset` also clamps for a menu above the preview |
| Press before open | `ContextMenuPressGestureRecognizer` on messages, chat rows, avatars and folder tabs: progress after 0.15 s, 20 pt allowable movement, hold 0.4 s (0.325 s on iPad), growth by 8 pt on the long side and shadow 0.3 / radius 20 on a 0.6 / 0.4 s spring at up to 120 Hz; release 0.85 / 0.35 s; Reduce Motion keeps scale 1 | The effect runs on the source view instead of a pre-presented overlay; `presentTelegramContextMenu` takes the grown view over and restores its base transform. Folder tabs (`.menuOnly`) settle back when the menu opens and cast no shadow (text only). Replaces the Telegram 0.1 / 0.26 s recognizer, the 0.3 s long presses and the 0.98 shrink |
| Open menu touches | One `ContextMenuTouchRecognizer` on the menu root (cancels and delays nothing) plus the opening finger: preview pan after 10 pt with rubber band only while the finger is off the menu and spring back on release; dismissal tap 45 pt / 1.5 s; outside finger hands off to scrubbing; 0.15 s selection delay for touches that begin on the menu; release outcomes A–N | Touches in the reaction strip, in the selectable quote text and in the scrollable chat preview stay with those views. The opening finger still scrubs reactions |
| Native calls | `ContextMenuNativeAnimation`: `UIViewSpringAnimationBehavior` pan behavior (0.15 / 0.996, tracking 0.8 / 0.4 smoothed 0.08, release 0.85 / 0.5) and highlight behaviors, `_animateUsingSpringBehavior:tracking:` inside 48–120 Hz reason 0x100026, each selector-checked with the public `UIView.animate(springDuration:bounce:)` fallback | The menu glass is the system's flexible `_UIViewGlass` set with `_setBackground:` (variant 0, not adaptive, flexible, flex variant 5, no grouping; `_setEnabledWithoutSolarium:` only where iOS 27 has it), whose `_UIFlexInteraction` stretches the glass toward a finger that touches the open menu and drags; public interactive `UIGlassEffect` only without those calls. Before `de791738` iOS 26 lacked `_setEnabledWithoutSolarium:`, fell back to the public glass and never bent, since the menu's rows sit beside that glass |
| Highlight | Shared highlight: frame 1 / 0.12 s, alpha 1 / 0.3 s, appears in place below 0.05 presentation opacity, inset 10 with radius min(menu radius − 10, h / 2), selection haptic on every change | Menu radius 30 keeps the existing 20 pt highlight |
| Escape | Escape key and `accessibilityPerformEscape` dismiss; the dim view is a VoiceOver Close element; focus moves into the menu | The menu root takes focus only when nothing is focused; otherwise the focused view's controller carries the Escape command, so the composer keeps its keyboard |
| Menu look | Unchanged: Telegram spring appearance, reactions strip, quote selection, submenus, keyboard-window hosting | — |

Proofs:

- Deterministic: `-ui-probe-context-menu-interaction` (`ContextMenuInteractionProbe`, DEBUG only) passed on iPhone 18 Pro
  iOS 27.0: 10,201 rubber-band vectors, native pan trace and preview centers, press samples, hold durations, 60/120 Hz
  spring independence and momentum, 12 native release cases, selection delay; private spring behavior available.
- Simulator smoke (iPhone 18 Pro, iOS 27.0, idb): chat-row preview opens on hold and stays open on release (A); outside
  tap dismisses (M); row tap after a preview menu opens the chat (F9); message menu with reactions, tap on copy runs
  copy (N, pasteboard checked); tap on the preview edge dismisses (E); a slow drag from the message onto reply opens the
  menu under the same finger and selects reply (G); Escape with the keyboard up dismisses the menu and keeps the
  keyboard; avatar menu, outside drag over 45 pt (J) and preview move 30 pt (K) keep it open; folder-tab menu, row
  touch dragged off the menu keeps it open (F); folder taps and list scrolling still work.
- Xcode MCP 10-17, one finger with `mt`: on the BetterTG test chat row, the opening finger dragged through archive and
  released outside kept the menu open with nothing chosen (B); dragged above the preview, it kept the menu open (C);
  dragged into archive and back to the preview, it kept it open (D). With the menu open, a touch below the menu dragged
  onto pin pinned the chat (H; unpinned again with a tap); on the chat preview the touch goes to the scrollable topic
  list by design (`touchOrigin` returns nil for `.chatPreview`), so I was checked on a message: a touch on the bubble
  dragged onto copy copied the message (I, pasteboard checked).
- Not proven: preview pan visuals mid-drag; VoiceOver escape (the Simulator doesn't run VoiceOver); 120 Hz and haptics on
  a physical device. iOS 26 runs the same gesture code; its morph is checked under "Liquid morph" below. Device-interaction multi-touch was
  first rejected by automatic approval review under the old AGENTS.md rule; `27635bdf` allows Xcode MCP, and the next
  section has the multi-touch proofs.

Glass flex, 10-24 (iPhone 17 Pro iOS 26.5 `8108A92F`, headless, agent-device in T3's Device panel, LLDB): before `de791738` the menu's `_UIFlexInteraction` sat on the public fallback `UIVisualEffectView` and a touch on a row dragged out of the menu left the glass still in every frame; after it the interaction sits on the menu view itself and the same drag moves and stretches the glass toward the finger and back, as the system menu and CustomContextMenu's own menu do on iOS 27 (ContextMenuLab on iPhone 18 Pro iOS 27.0, the same drag through idb). The last sentence that stood here, that the finger which opened the menu never bends it, held only when that finger is off the glass at opening; see 10-31 below.

Glass flex and system audit, 10-31 (iPhone 17 Pro iOS 26.5 `8108A92F`, UIKitCore 23F77, agent-device `gesture drag` and `gesture pan`, recordings compared frame by frame):

- How the system does it: the flex pan begins at `touchesBegan` and `gestureRecognizerShouldBegin:` hit-tests the current location, so a touch off the glass fails it for good. Touch continuation (`_addTouch:forEvent:`) delivers the running finger when the menu presents. Files' `•••` menu opens under the finger: the glass follows it for the whole hold. ContextMenuLab's message menu opens below the finger: dragged down onto the rows, the system glass stays still, as trace N1 showed.
- BetterTG's rule, the user's decision later on 10-31 (`566797ec`, replacing the handoff of `13650f39` and `7aff585e`): flex belongs to a touch that begins on the menu. The finger that opened the menu never flexes it, even where the menu opens under that finger, which the user reads as an accident of the system. A finger that slides from the message onto the menu only highlights the rows, with the message locked; off the menu the message follows it again, never toward the menu, within the 15-point rubber band. A touch that begins on the menu keeps the message still. A submenu's glass carries its rows and swells under a touch as the system's does; before, its glass lay beside the rows and failed the pan's hit test.
- A drag that begins on the menu no longer scrolls an overflowing message's content (`ed779517`); a drag on the message still does.
- Checked and already the same: a tap on the background only closes a button menu (Files, nothing passes through); no swipe-down dismissal with actions (`rubberbandingEdges == 15`); no `setShouldDismissMenuOnSceneDeactivation:` call in the menu classes; auto navigation, the selection delay and the highlight springs; iPhone is portrait-only, so rotation does not apply.
- Ported the same day, checked on iPhone 18 Pro iOS 27.2 with `-ui-probe-context-menu-screen` (`ContextMenuScreenProbe`, no account needed) and in the UI test chat on iOS 26.5:
  - Action timing: the handler runs as the close starts (`contextMenuView:didSelectElement:` passes it as `alongsideActions`), 0.25 s before the menu is gone; reply, select and the back menu's pop ran without a jump.
  - Selection: the chosen row stays highlighted 0.1 s (`autoUnhighlightTimer`).
  - Titles wrap to 3 lines (`setPreferredNumberOfLinesForTitle: 3`).
  - Reduce Motion: the menu fades in place, previews use the 0.4 / 1 spring (Research/README.md, iOS 27.0).
  - Dynamic Type: row text, icons and insets scale through `UIFontMetrics`, up to `accessibilityMedium`, because the menus don't scroll yet.
  - Hardware keyboard: up and down, Return, the forward arrow into a submenu and the back arrow out of it, type select, also with the composer focused. Pointer: a click selects and hover highlights without the tick, opening a submenu like a resting finger.
- Not ported, by the user's choice for now:
  - Long menus. `setMenuMaximumHeight: 520` with scrolling, a truncation detent (`closestScrollTruncationDetentToHeight:`), a gradient mask and auto-scroll while scrubbing. BetterTG's menu and submenus do not scroll, so rows past the screen cannot be reached.
  - Order. A menu attached above its source reverses its actions (`_updateActionsViewReversesOrderForAttachment:`), keeping the first one nearest the finger.
- Kept on purpose, not counted: the red chevron on destructive rows, the preview, the blur behind the menu (Telegram's context sources set `blurBackground = true` too) and the reaction strip.
- Ported later on 10-31, read from a live iOS 27.2 menu (`_UIContextMenuPlatformMetrics_Glass` and its layout) and checked on 27.2 with the probe and on 26.5 in UI test (`df777132`): width 250, radius 32, 42-point rows with 82 for three lines, text at 64 or 28, icon centre at 40, chevron centre 31 from the trailing edge at full alpha, title and icon at 0.96, separators inset 24, 1 point, label at 0.08, 21 points between rows across one. At `accessibilityMedium` the menu is 370 wide with 16-point margins, without leading icons or a line limit; the row is about 1 point taller than the system's 67.3.
- The liquid morph now runs on every menu; see [Liquid morph](liquid-morph.md).
- Not proven: keys went through the handler in the probe, since agent-device can't send arrow keys; pointer input was not driven on any runtime; a physical device and haptics. Agent-device drags have two points, so message → menu → back in one touch was not driven: its parts were (up off the message, down across the menu), and the follow depends only on where the finger is.
- The system's dim for reference: black 0.20 light, 0.48 dark, with no blur behind the menu.
- The opening finger on the system menu, driven by `gesture drag` from a message onto its rows: the glass stays still on 26.5, 27.0 and 27.2 simulators. The user saw it bend where the menu opens under the finger, and not from a message; see BetterTG's rule above. In the 27.2 lab a touch from a row dragged above the preview also moved the system's message about 5 points at the end, while the user sees no movement in iMessage on a device. BetterTG follows the user.
