# BetterTG identity (user decisions)

Telegram is the reference for behavior, gestures, layout logic and edge cases. Appearance follows BetterTG main.
The current continuation contract is [goal.md](goal.md), refreshed from the user's corrections through 2026-10-29.
The dated entries below preserve history; later implementations supersede earlier mechanisms and remaining-gap notes.

- Full-width bars with iOS 27's light blur under them, on iOS 26 too; content scrolls under them. One Telegram navigation
  bar on every screen, its buttons in Liquid Glass platters grouped as UIKit groups bar items, the chat's title in a glass
  pill, and the platters morphing between screens on push and pop as Telegram 13's do (user decision 2026-10-28, which
  replaced "no glass button backgrounds").
- Folder picker at the bottom: Liquid Glass with liquid lens and interactive glass (`3df82a3`), blur behind it, unread
  counts (`208f549`). Forward to uses the same picker.
- Context menus: the custom Telegram menu with glass (`TelegramContextMenu`, `3656153`), gestures from
  CustomContextMenu.
- Composer (updated 2026-10-28/29): full width with the safe area on the bar's blur when docked; above the keyboard it
  becomes interactive Liquid Glass with rounded corners and 8 pt side insets, without a layout jump. This includes
  single-line input: the text view itself lives inside the glass's contentView so its touch drives the glass response.
  Plus-to-field spacing equals the edge spacing on both sides. The Telegram EdgeEffect gradient remains behind it
  (the inverted list cannot use the system edge effect); the outline does not show under the home indicator.
- Glass transitions lend live views through TelegramGlassLoan and restore their constraints, preserving UIKit's tint
  and compositing. A screen with asynchronous first content uses TelegramTransitionReadiness, with a bounded 0.5 s wait.
- Quote comes from text selection inside the open message menu; no separate item. The reaction strip does not slide in
  from the side.
- Topic search starts hidden and collapses before the list scrolls, as in the main list; the same in Forward to.
- Forward to: bottom folder picker, compact rows without last message, search in the navigation bar. Ordinary selection
  opens the chat with a "Forward message / user: text" block in the composer; Saved Messages sends immediately with a
  toast. The separate Select mode supports multiple destinations with its comment field and send panel (2026-10-25).
- Regular icons, not glass variants with the background removed.
