# Liquid morph of menu buttons — 2026-10-12

Source: Telegram iOS `telegram-upstream` 58ce7d6688, f44a25a649, 11a469d1f8, 7c2cfd6a1f (read at `7c2cfd6a1f`):
`docs/context-menu-liquid-morph.md`, `submodules/TelegramUI/Components/LensTransition` (`Bridge/Sources/LensTransitionRuntime.m`,
`Bridge/Sources/Identifiers.inc`, `Sources/LiquidMorphTransition.swift`, `Sources/LensTransitionContainer.swift`),
`prototypes/ContextMenuMorph/Tests/LiquidMorphTests.swift`.

| Area | Port |
| --- | --- |
| Runtime adapter | `BTLiquidMorphDriver` (Objective-C, bridging header): Telegram's `LTTransitionDriver` with the same XOR-encoded identifier table. It subclasses UIKit's liquid-morph presentation animation at runtime, overrides the source, pivot, accessory and background hooks, and starts it with `initWithUIController:previousAnimation:` and `performTransition`. Every method it calls or overrides is checked against its full Objective-C signature; an in-flight driver of the same source is passed as `previousAnimation` so UIKit hands the running morph over. No private name appears in plaintext in the built binary (checked with `grep`) |
| Swift wrapper | `ContextMenuLiquidMorph`: preview validation, the 10 × 10 pivot at the attachment point, completion handed back on the next main-queue turn after UIKit's cleanup, `interruptingCurrent` for a close that takes over a running opening, and a 120 Hz display-link claim that ends at completion or after 1 s |
| Menu integration | `TelegramContextMenuPresentationStyle.sourceMorph`: the menu takes the button's place (top on top in the upper half, bottom on bottom in the lower half, left or right edge by screen half, screen clamp). The button morphs into the menu glass, and an alpha-override assertion hides it for the menu's lifetime. A close morphs back into the button's current presentation transform and takes over an opening still running. A second assertion keeps the closed menu hidden through UIKit's cleanup, and the menu alpha drops to 0 before that assertion ends. Without the runtime, with Reduce Motion, or when the button has left the window, the menu opens next to the button with the Telegram spring, and a close after the button left fades at once |
| Close timing | UIKit completes a close after about 1.6 s. The menu stops taking touches when the close starts, and the chosen action runs at 0.7 s (Telegram's recorded end of the visible close motion) instead of after settling. A menu that is still closing does not block the next one: it stays alive in a closing list until its completion |

Per-control decisions:

| Control | Decision |
| --- | --- |
| Gallery More (`ChatViewAlbum.moreButton`) | System `UIMenu` replaced by the custom menu with the morph, so the gallery menu matches the rest of the app |
| Composer attach (`ChatBottomArea.attachmentButton`) | A tap opens Telegram's attachment sheet; while editing a message, the custom menu (Emoji) morphs out of the button. The send button's send options and the attachment sheet's menus also use the morph |
| Video playback rate (`rateButton`) | Not applicable: a tap cycles rates and opens no menu |
| Video quality | Not applicable: the player has no quality control |
| Media preview before sending | Not applicable: no button there opens a menu |
| Record button retry/discard (`actionButton.menu`) | Kept as a system `UIMenu`, which UIKit morphs natively. The same button owns hold-to-record touches |
| Classic navigation bar items with menus | Kept as system `UIMenu`s, morphed by UIKit. Telegram's morph targets glass header capsules, which BetterTG's classic chrome does not use |
| Folders, messages, chat rows, avatars and other menus | Since 10-31 (`129f9d96`, the user's decision, reversing 10-24): the glass grows out of a clear 10 × 10 attachment point, as UIKit's menus with `sourcePreviewMorphsToMenu` NO do |

With a preview the morph draws in a host under `previewPanView`, and the preview stays in front while the morph opens and closes, because it may cross the menu on its way to or from its source. The source takes its content back and `onDismiss` fires when the preview lands, about 0.24 s into a close; the overlay stays, without touches, until UIKit's morph completes. Reduce Motion fades the menu. Checked on iPhone 18 Pro iOS 27.2 with `-ui-probe-context-menu-screen` (message, submenu, button, action and reopening during a close) and on iOS 26.5 in UI test and the chat list (message, chat row, folder tab). Avatars, the tip and a menu in the keyboard window were not driven with the morph.

Proofs:

- Deterministic: `-ui-probe-context-menu-liquid-morph` (`ContextMenuLiquidMorphProbe`, DEBUG only) passed on iPhone 18 Pro
  iOS 27.0 with Telegram's prototype checks: runtime supported, completion with UIView animations disabled and release of
  the native coordinator and context, round trip restoring hierarchy and rejecting a concurrent morph, a close at 0 and
  0.3 s taking over the opening with one completion each, and overlapping visibility assertions keeping the model alpha.
- Simulator smoke (iPhone 18 Pro, iOS 27.0, idb): composer attach menu opens in place of the hidden + button, closes on an
  outside tap without showing the open menu again, and Emoji, Stickers & GIFs opens its panel; gallery More opens in place,
  survives an open-then-close and a reopen during the closing morph, and Open in Chat navigates with no overlay left; the
  message menu is unchanged.
- Found and fixed during smoke: a reopened menu replaced the closing controller as the only strong reference, so the
  old controller deallocated before its close completed and left its overlay on screen. Closing controllers now stay in
  a list until their completion (log trace: the old close completion arrived with a nil owner).
- Morph frames (10-17, 60 fps Xcode MCP recordings of gallery More): the glass grows out of the button over about
  0.23 s and shrinks back on close; the counter stays under the opening glass and shows through the thinning closing
  glass for about 50 ms (F26). Reduce Motion runtime: plain presentation, see the gestures section above.
- Keyboard up (10-17, Xcode MCP in UI test, 60 fps `/tmp/kbmorph.mp4` frames 1464-1478): with the system keyboard
  showing, holding the send button grew Send Without Sound and Schedule Message out of it in about 0.2 s, above the
  keyboard, which stayed in place; while editing, the attach button morphed into its Emoji menu the same way.
- iOS 26 (10-17, iPhone 17 Pro iOS 26.5 Simulator, `-ui-probe-context-menu-liquid-morph`): the probe passed with
  the runtime supported, so iOS 26 morphs as iOS 27 does. An unsupported runtime takes the same
  `usesLiquidMorph == false` branch as Reduce Motion, whose plain presentation is proven above.
- Not proven: 120 Hz on a device.
