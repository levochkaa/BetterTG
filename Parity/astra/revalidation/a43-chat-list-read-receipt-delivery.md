# A43 chat-list read-receipt delivery — 2026-10-03

- Baseline `bc7e3f4`: `ChatListCell.deliveryState` reads the immutable Chat's outgoing read watermark, but generated
  `updateChatReadOutbox` has no subscriber. Folder rows already observe `CustomChat.objectWillChange`; missing TDLib feed,
  not missing cell rendering, is the narrow defect. No broad unread-badge or timeline rewrite is included.
- Add the receipt to Root's existing account/client-scoped observation and active-read projection. Patch only the matching
  Chat watermark in main/custom/archive instances; deduplicate shared object identities and unchanged values. No getChat
  round trip. Revision stamps preserve a newer accepted receipt across earlier getChat/hydration/rebuild results while
  respecting later read and complete-snapshot boundaries. Existing source/epoch retirement remains unchanged.
- References: Telegram current `6ad963e5b62d354da79040f388ae2b9132fb17b8`,
  `ChatListUI/Sources/Node/ChatListItem.swift`3393–3411 and1590–1591; pre-Liquid
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, same path3093–3111 and1510–1511: account read counters drive
  Delivered/Read and accessibility independently of unread badges. TDLib `022d6020`, `td_api.tl`10417–10418;
  `MessagesManager.cpp`9938–9950,27270–27284 sends the dedicated update;25560–25565 only schedules database persistence.
  Last-message/position updates are not guaranteed companions. No upstream infrastructure imported.
- Three Swift files formatted together; `build-Debug-20261003-032256-23469-20517.log`: PASS9s, complete warning/error scan
  empty. Independent source review found no introduced P1/P2. Audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5,
  PID `24065`, source `bc7e3f4` plus this delta: root projection, list authority and insertion probes all pass.
- Expanded probe exercises production scoped NotificationCenter delivery, authority and field patch; multiple distinct
  folders/archive instances, shared-instance single publication, duplicate/current/wrong-chat/foreign-source handling,
  old-client queued delivery rejection, stale hydration and newer read/snapshot precedence. Actual `ChatListCell.configure`
  changes AX from Delivered to Read without a new last message. Its private center/fixture makes no server calls and does not
  inject updates into the user's Root. RootVM subscriber/table wiring is source-reviewed, not runtime-injected. The fixture
  retains a lease while switching its fake source to test field ordering; production source changes still invalidate leases,
  covered by the existing retirement regression. No live peer-read, full list receipt smoke or server mutation claim.
