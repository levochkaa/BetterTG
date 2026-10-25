# Chat restoration history/import foundation — 2026-10-02

- A30b2 worker `760f8cc` integrated as `2490198`. Detached display values preserve raw source IDs, album members, presentation
  metadata and pagination cursor without mutable wrappers or in-flight mutation flags. Reconciliation rebuilds albums by source ID.
  A separate raw latest cursor bridges toward the seed; it does not jump directly to the old history cursor.
- At most four reads run per batch, with visible seed IDs first. Source/generation and per-message revision checks bracket metadata
  hydration and delivery; permanent deletion tombstones prevent resurrection. Partial reactions/pins do not establish that a stale
  body is current: invalidated reads stay unresolved for explicit retry. Full accepted messages satisfy superseded reads. Latest-page
  tokens reject stale/replayed/reentrant delivery. Errors never auto-poll or imply deletion.
- Exact missing result verified in pinned TDLib `022d6020`: `Requests.cpp:592–607` → `Td.cpp:1392–1407` yields 404 `Not Found`.
  Other errors retain a retryable seed. Import tokens allow one local completion into a retained same-account route before retirement;
  removed/cross-account/retired owners reject it. None authorizes a send on an obsolete client.
- Four Swift files formatted together in the worker; primary combined build
  `.build/logs/xcodebuild/build-Debug-20261002-175112-65343-2137.log` passes without warnings (11s).
  PID `66007`, `-ui-probe-chat-restoration-state` passes value/album/cursor, import and suspended read/hydration/token checks with
  zero server reads/sends. Repeated at `901af79`, PID `72550`. Evidence: `.build/ui-probe-evidence/astra-a30b2-state-primary` and
  `astra-a23a-primary`; worker README/log copied separately. Existing pinned ChatInterfaceState references apply.
  Chat navigation is still disabled; live history, file-import controllers, anchor/focus and shared same-epoch update ordering need wiring.
