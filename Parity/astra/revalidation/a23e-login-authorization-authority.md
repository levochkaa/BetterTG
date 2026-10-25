# A23e login authorization authority — 2026-10-02

- `5e2f58a` (worker `b5e001b`) publishes replayable accepted authorization state keyed to the account/client epoch.
  Handoff clears readiness before replacement; Login clears credentials/hint and cancels queued work. A fixed-account session
  accepts its replacement client, but a foreign-account transition permanently revokes it. Duplicate states retain current input.
- Submit captures client, stage and request identity before dispatch. Every dispatch/completion validates that identity; old
  completions cannot clear newer busy/input state. Country lookup and country/account callbacks use the same authority.
  Root replaces a revoked Login even after a coalesced A→B→A. Unsupported authorization stages remain non-submittable.
  Cancellation cannot retract an already dispatched RPC; credentials are not logged, and Swift String zeroization is not promised.
- Generator and emitted auth notification use the normal scoped transport. Accepted-state replay replaces informational
  `getAuthorizationState` reads. Regeneration leaves `Td+Generated.swift` unchanged (SHA256
  `1d4722587534754ed628995aa1dbcb6bb6628aa1e8f2d56d9b86b056e669fa41`).
- Reference: pinned current/pre `AuthorizationUI/Sources/AuthorizationSequenceController.swift` 39–124,340–342,519,942 /
  39–124,190–195,477,900. Pinned TDLib `GetAuthorizationState.swift` documents informational use only; production follows
  accepted `updateAuthorizationState` and captured phone/code/password authentication APIs. No upstream infrastructure copied.
- Nine Swift integration paths formatted together (generated path excluded by repository formatter); integration build
  `build-Debug-20261002-202608-8127-22497.log`: PASS11s, zero warnings. First actual Login probe failed because UIKit normalized
  the cleared placeholder to nil. Diagnostic proved text empty, hint nil, input disabled and old action invalid. `4953838` accepts
  nil or empty without changing production; initial failure and Boolean-only diagnostic are retained.
- One-file final format/build `build-Debug-20261002-203027-28086-32623.log`: PASS7s, zero warnings. Audit Simulator PID `31259`,
  source `5e2f58a` plus the later-committed `4953838` probe: auth, Root list, Chat updates, viewport and composer entity probes pass.
  Actual Login view covers queued/suspended/reentrant/deinit cancellation, duplicate submit, same-account replacement, foreign
  terminal revocation and scoped generated dispatch using private injected state/requests. Auth/account-store/clipboard writes: zero.
- Authenticated root opens and returns from Home in the same launch after accepted-state bootstrap changes. Evidence:
  `.build/ui-probe-evidence/astra-a23-auth-primary`; root screenshot contains private chat data and is not a shareable artifact.
  Real code/password/country actions, actual account switching and server authentication remain unverified.
