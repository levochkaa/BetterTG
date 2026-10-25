# Liquid Glass folder picker and context-menu restoration — 2026-09-05

- User request: restore the existing folder picker and context-menu UI from before the parity classic-shell conversion;
  retain any later behavior and action work. The exact visual regression is `64625ed`.
- Reversed only that commit's styling hunks in `MainView.swift` and `TelegramContextMenu.swift`. The folder picker again has
  a 42pt glass capsule inset 16pt, a clipped scrolling viewport and a moving glass selection over the full-width background blur.
  Menus again use regular Liquid Glass, 30pt outer corners and 20pt selection corners. The shared menu source matches `64625ed^`.
- Retained later localization, TDLibKit 2 migration, forum routes and folder reselect scroll repair. Folder actions, unread
  badges, page transitions, extracted previews, keyboard hosting and context action handlers are unchanged by the restoration.
- Build: SwiftFormat checked both changed Swift files; `./build.sh build --simulator-id 8108A92F-7E93-49C8-87F4-FA53A5A40A99`
  succeeded on Xcode 26.6 / iOS 26.5 with zero warnings or errors. Log: `.build/logs/xcodebuild/build-Debug-20260905-163828-11292-31865.log`.
- Runtime: launched through `./build.sh run --skip-build` on the same iPhone 17 Pro / iOS 26.5 (PID `12092`).
  CLI idb/simctl captures show the restored glass picker, folder tap loading channels, content swipe returning to All, strip
  scrolling that fully reveals the groups badge and later tabs, and groups selection centering its glass capsule. Before/after
  PNG/JSON evidence is under `.build/ui-probe-evidence/glass-restore-20260905/` (01/02/04 before, 05–14 after).
  Reselecting groups returns the scrolled list to the first pinned row; the shared folder menu shows all six actions in the
  restored glass surface, and Edit Folder opens the correct configuration and returns via Back without saving. No new control
  clipping or overlap was found in this bounded smoke. App remains on the groups list with the picker visible.
  `SMOKE.md` records the exact checks and limits: separate chat/message menus were not repeated after restoration and no
  server mutation action was submitted.
