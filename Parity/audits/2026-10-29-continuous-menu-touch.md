# Continuous menu touch — 2026-10-29

Six entry points pass a real hold → move → release gesture on `46ef736d`.
This pass changes no production code. It verifies the callers' existing `tracking: gesture` handoff separately.

## Build and method

- Branch `t3/refresh-goal-prompt`, worktree `t3-290b274e`; iPhone 17 Pro Simulator, iOS 26.5,
  device `8108A92F-7E93-49C8-87F4-FA53A5A40A99`.
- Xcode 27.1 (27A9275), `./build.sh build`; source build log
  `build-Debug-20261029-225547-97137-26012.log`, no warnings or errors.
  Installed `BetterTG.debug.dylib` SHA-256:
  `452b3b7e38e6d784549207e83c030c68f00fbaa7d89bdc1bf5642eac64e0fe3c`.
- Final `./build.sh build` passed in 24 s; complete log `build-Debug-20261029-231237-21250-21645.log`
  contains no warnings or errors. The installed and built dylibs still have that same hash.
- T3 Device panel's bound `agent-device gesture drag`: one pointer, source hold 700 ms for glass buttons,
  800 ms for rows, move 350 ms, destination hold 200 ms. No second tap selects the action.
- Each menu was first opened to measure the action's rectangle, then dismissed. A fresh snapshot supplied
  the source and an underlying view whose centre falls inside that rectangle after the menu opens.
  The CLI resolves both endpoints before touching down; the underlying view is only a coordinate anchor.
- Recordings show the action highlight before release; the resulting screen was checked after dismissal
  finished. Immediate snapshots sometimes still contained the closing overlay, so they were not treated
  as failures or final state. Recordings have variable frame rate and do not prove 120 Hz or device timing.

## Results

| Entry point | Continuous gesture and observed result | Evidence in `/tmp` |
| --- | --- | --- |
| Settings/accounts | `(364,84) → (201,136)` crosses Add Account and highlights the current account. Release closes the menu; Settings is tappable again, search stays unfocused, no account is added or switched. | `bettertg-accounts-continuous.mp4`, `bettertg-accounts-gesture-frames.jpg` |
| Chat Send, keyboard visible | Saved Messages, temporary text: `(367,506) → (182,506)` selects Set a Reminder and opens its date picker. Cancel restores the text and input. | `bettertg-chat-send-continuous.mp4`, `bettertg-chat-send-after.png` |
| Attachment sheet Send | One existing colour-pattern test asset and temporary caption: `(359,802) → (176,802)` selects Set a Reminder. The sheet closes, its asset enters the composer, and the date picker opens. Cancel preserves that draft. | `bettertg-sheet-send-continuous.mp4`, `bettertg-sheet-send-after.png` |
| Group member list | BetterTG test's existing test bot: `(201,153) → (201,226)` selects Send Message and opens the bot's chat. Nothing is sent; member tags and rights stay unchanged. | `bettertg-member-continuous.mp4`, `bettertg-member-after-crop.png` |
| Profile Links | Existing test-game link: `(201,517) → (182,592)` selects Show in Chat and opens UI test at that link message. | `bettertg-links-continuous.mp4`, `bettertg-links-after.png` |
| Profile Files | Existing test JPEG document: `(201,503) → (201,568)` selects Show in Chat and opens UI test at the document album. | `bettertg-files-continuous.mp4`, `bettertg-files-after.png` |

Both reminder pickers were cancelled before confirmation. The temporary composer text and imported test asset
were removed through the UI; the empty composer showed Record voice message, with no Send or attachment-close
button. No message or reminder was created, no existing message or Photos asset was deleted.

## Source contracts and limits

- `MainView.showAccountSwitcher`, `ChatBottomArea.showSendOptions`, `AttachmentSheetViewController.showSendOptions`,
  `PeerProfileMembersViewController.memberLongPressed` and `PeerProfileViewController.sharedRowLongPressed`
  pass the opening recognizer to `TelegramContextMenuController`. It retains the initiating touch session,
  follows its location, highlights the row and performs it on release.
- Telegram reference `telegram-upstream/master` = `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:
  `submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift`, `externalUpdated` /
  `externalEnded`, forwards motion and release to `actionsStackNode`; `submodules/ContextUI/Sources/ContextController.swift`
  defines the highlight-move/finish contract. BetterTG's chosen touch model remains the UIKit reconstruction in
  `CustomContextMenu/Research/Interaction/README.md` and `ContextMenuTouchSession`, including handoff hysteresis.
- Folder invitation: `ChatFolderEditorViewController.inviteLinkLongPressed` passes `tracking: gesture`, but this
  pass found no dedicated test folder in Settings. It did not create an invitation or inspect/export the user's
  existing folder links. Runtime selection remains **unverified**.
- The member check covers the separate member list of a two-member group. The embedded Members pane used above
  five members remains unverified. Files and Links were checked separately; Voice, Audio and the media grid were
  not. The grid is explicitly excluded by `sharedRowLongPressed`; these results do not claim a grid context menu.
- Back has earlier evidence and was used for navigation here, not retested with a continuous gesture.
  This pass does not close submenu, iOS 27, physical-device, multi-account or full-parity checks.
