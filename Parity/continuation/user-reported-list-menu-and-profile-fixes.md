# User-reported list, menu and profile fixes — 2026-09-05

- Single/double delivery checks use Telegram's `PresentationResourcesChatList.generateStatusCheckImage`
  stroke geometry. A fixed trailing status container isolates unread/pin/mute from summary compression
  and removes hidden arranged-view width conflicts; pin is hidden whenever unread owns the slot.
- Expanded and active list/chat searches use a 36pt field with 8pt vertical padding. Pinned content and
  chat navigation share one background material, with no overlapping independent blur surfaces.
- Message menus retain the approved glass style, align with the actual bubble edge, keep Forward in
  the main action section and expose one Delete entry with a Back/available deletion-modes submenu.
- Avatar previews request account-scoped large photos during presentation, preserve the existing
  image and dissolve to the decoded result. Profile/Search actions resolve the represented peer.
- Profile actions occupy one row; Edit remains in navigation. Shared media uses the actual folder
  picker component (plain items without folder actions) with its glass selection and scrolling logic.
- Leaving selection via Cancel, last deselection or removal of selected messages resets all cells,
  including unselected indicators. The count title has symmetric navigation bounds around Cancel.
- Validation: SwiftFormat on all 12 changed Swift files, warning-free `./build.sh build` on Xcode 26.6
  / iOS 26.5 (`build-Debug-20260905-174328-31642-5978.log`); wrapper launch on the existing simulator.
  Simulator screenshots/hierarchy confirm list/chat search 8pt bottom gaps, trailing unread badges, one-row profile actions and glass tabs, avatar Profile/Search, root Delete/Back, exact bubble-edge menu alignment, centered selection title and complete cleanup on Cancel/last deselection. See `.build/ui-probe-evidence/parity-fixes-20260905/stage1/SMOKE.md`. Physical-device layout proof remains pending.
