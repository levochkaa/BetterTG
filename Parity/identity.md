# BetterTG identity (user decisions)

Telegram is the reference for behavior, gestures, layout logic and edge cases. Appearance follows BetterTG main.

- Full-width blurred navigation and tab bars with safe area; content scrolls under them. One classic Telegram navigation
  bar on every screen, with chat-list/chat sizes and Back button, no Liquid Glass islands, no glass button backgrounds
  and no glass flashes during push/pop.
- Folder picker at the bottom: Liquid Glass with liquid lens and interactive glass (`24657e8`), blur behind it, unread
  counts (`75184a2`). Forward to uses the same picker.
- Context menus: the custom Telegram menu with glass (`TelegramContextMenu`, `24d5b2f`), gestures from
  CustomContextMenu.
- Composer (`3877e60`): square and full width with the safe area when the keyboard is hidden; with the keyboard all
  corners round and 8 pt side insets appear, animated. Non-interactive Liquid Glass. Plus-to-field spacing equals the
  edge spacing, on both sides. With the keyboard, a linear gradient on the Telegram EdgeEffect curve sits behind the
  composer (the inverted list cannot use the system edge effect). The glass outline does not show at the corners or under
  the home indicator.
- Quote comes from text selection inside the open message menu; no separate item. The reaction strip does not slide in
  from the side.
- Topic search starts hidden and collapses before the list scrolls, as in the main list; the same in Forward to.
- Forward to: bottom folder picker, compact rows without last message, search in the navigation bar, no comment field or
  send panel. Tapping a chat opens it with a "Forward message / user: text" block in the composer.
- Regular icons, not glass variants with the background removed.
