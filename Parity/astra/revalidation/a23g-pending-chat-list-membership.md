# A23g pending chat-list membership — 2026-10-02

- `1e339bb` (worker `551707e`) serializes pending hydration by account/client/chat/semantic list and exact destination folder.
  All four membership entry points share the production helper. Zero order and omitted lists in complete last-message/draft
  vectors remove rows and revoke pending insertion. A positive update during hydration coalesces into one follow-up read;
  only the latest intent may append, with its accepted order/pin. Remove→re-add can proceed before the canceled old RPC returns.
  Old success/nil/error cleanup cannot clear replacement ownership. Source/folder/root-ticket changes fence terminal application.
- References: pinned TDLib `td_api.tl`10398–10406,10430–10433; `MessagesManager.cpp`33622–33658,27091–27094,27128–27131
  confirms complete current membership vectors and omitted zero-order lists. Pinned current/pre `ChatListNode.swift`
  3327–3365 / 3477–3515 serializes accepted list transitions. No Postbox/SignalKit infrastructure copied.
- Five Swift files formatted together; `build-Debug-20261002-221330-92632-19395.log`: PASS16s, zero warnings. Audit Simulator
  source `1e339bb`, PID `94658`: actual helper/CustomFolder/RootListAuthority probe passes sixteen suspended hydrations:
  pre-dispatch removal, late success/nil, coalesced order/pin, omission, re-add before old reply, distinct lists/accounts/clients,
  replaced folder/root ticket, rejection and retry. Root/scoped-update/forum-restoration/classic-navigation regressions also pass.
- Evidence: `.build/ui-probe-evidence/astra-a23g-primary`; worker `.build/root-chat-insertion-proof/README.md` records its
  initial DEBUG fixture compile corrections and final clean build. No real account changes or server calls. RootVM notification/RPC
  wiring is source-reviewed, not exercised by the helper. Pending unread/user/non-position hydration, bulk rebuild A34 and scope
  notification ordering A35 remain open. This proof establishes membership, not complete latest message/draft payload parity.
