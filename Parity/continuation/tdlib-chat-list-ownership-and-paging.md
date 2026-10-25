# TDLib chat-list ownership and paging — 2026-09-05

- `TelegramChatListStore` consumes the active client's ordered updates before dispatching UI
  notifications. It retains chat/peer snapshots and all chat fields across partial updates;
  folder membership comes from positions, with `(order, chatId)` descending order and zero-order
  removal. Last-message and draft updates replace the full position set, including removals.
- RootVM projects this cache into stable CustomChat objects. Folder metadata hydration cannot lose
  chat updates arriving before the corresponding folder UI exists. Account/client changes discard
  old caches and fence async folder/page work. Read-inbox/outbox updates feed the actual row state.
- Main, archive and custom folders use `loadChats` with repeated short pages and 404 as exhaustion.
  Near-bottom scrolling loads more; failures expose Retry. The chat-list UI no longer uses `getChats`
  or per-row `getChat`/peer requests to discover list contents. Informational picker/action snapshots
  remain separate. `ChatListStoreDebugProbe` exercises order ties, movement/removal, partial read
  updates, retained native values and account/client isolation without making server requests.
- Validation: SwiftFormat on all task-modified Swift files; warning-free `./build.sh build` on
  Xcode 26.6 / iOS 26.5 (`build-Debug-20260905-175331-35225-7160.log`). The opt-in native-cache probe passed all nine checks on a real TDLib model, without server mutations. Main, custom-folder and Archive lists populated correctly after the snapshot fix below. A visible scroll sample does not establish a measured row-200 crossing.
