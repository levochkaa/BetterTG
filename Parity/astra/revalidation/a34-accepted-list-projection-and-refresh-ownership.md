# A34 accepted list projection and refresh ownership — 2026-10-02

- `1c13e0b` (worker `85cbcec`) retains typed latest-per-field deltas only for active rebuild/hydration/refresh reads. Raw Chat,
  peer and list RPCs have separate dispatch revisions: older accepted values cannot replace a fresher response. Explicit nil
  photo/draft/last values clear old fields; complete positions revoke omitted lists, newer partial positions override their list.
  A final synchronous reconciliation precedes folder installation; positive missing-row intents use the new exact folder owner.
- Pending insertion keeps its lease through actual helper admission, not only until hydration returns. A23 membership ownership
  remains authoritative. Requested peer IDs alone receive user deltas. Terminal/canceled/replaced leases clear retained values;
  repeated updates coalesce instead of appending a journal. Native RPC cancellation is not claimed.
- Main review found superseded refreshes retained projections until RPC return. `2e89c2a` (worker `29b7ce0`) adds synchronous
  per-chat refresh retirement and exact-identity cleanup. Rejected startup also closes its captured owner. Independent source
  review found no further introduced blocker; it did not exercise full RootVM/TDLib transport.
- References: pinned current/pre `ChatListUI/Sources/Node/ChatListNode.swift`3327–3365 / 3477–3515 serializes accepted list
  transitions. Pinned TD `td_api.tl`10398–10406,10430–10433,11473–11476 defines full positions/removal and warns `getChats`
  is informational. Existing 200-item reads/new group subscriptions are unchanged; this is not exhaustive chat-list hydration.
- Nine integrated Swift files formatted together; `build-Debug-20261002-224502-40819-31807.log`: PASS29s, zero warnings.
  Source `2e89c2a`, audit Simulator PID `44216`: actual reducer/insertion probe passes raw/peer/list boundaries, nil clearing,
  suspended rebuild/new-folder replay, late admission, remove→re-add/coalescing and suspended refresh retirement. Root membership,
  scope settings, source authority, scoped Chat updates, Forum restoration and native navigation regressions all pass.
  Fresh A34/A35 files timestamp `22:46:03`; evidence `.build/ui-probe-evidence/astra-a34-primary`. Authenticated root is populated;
  All→people→All selection was exercised without opening other chats or editing folders. This does not reproduce a live delayed
  rebuild. A dedicated full-new-Chat snapshot runtime case and unobserved Chat/group fields remain outside proof.
