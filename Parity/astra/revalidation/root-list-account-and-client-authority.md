# Root/list account and client authority — 2026-10-02

- A23a `955c37f` routes typed RootVM list/chat/user/unread/settings updates through accepted source checks at main delivery.
  Folder unread uses the event's client ID. List reads capture one client for every nested chat/user/group/folder RPC and check
  account/client plus root ownership epoch before publication. Full folder loads and per-chat refreshes also have request IDs;
  a detached folder cannot receive a pending append. Durable document outcome/delete handlers are unchanged.
- Legacy void auth notifications only wake a current-state read; they no longer blindly set the new account's logged-in flag.
  This does not migrate every authorization/topic subscriber or solve all same-client field-update races.
- Reference: current/pre `ChatListUI/Sources/Node/ChatListNode.swift` retains AccountContext at 1216/1213 and 1397/1391;
  current history subscription at 1934 uses that account. TDLib `getChats/getChat/getUser/getSupergroup/getBasicGroup/getChatFolder`
  and existing generated scoped update transport remain unchanged. No Telegram infrastructure copied.
- Five Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-180056-69882-3475.log` (9s), after correcting a missing Foundation import.
  Integrated `60a29cb`, PID `72550`: `-ui-probe-root-list-authority` passes actual ticket/scoped-delivery checks for delayed
  A→B, replacement client, unscoped event, A→B→A request epoch and mismatched owner. Five A30b2/A31/A29/A30a/A30b1 regression
  results pass in `.build/ui-probe-evidence/astra-a23a-primary`. Real RootVM/RPC wiring is source-reviewed; no real account switch,
  delayed server response or account/list mutation was performed.
