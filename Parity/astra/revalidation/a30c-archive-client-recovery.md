# A30c Archive client recovery — 2026-10-02

- `2e31805` opts Archive into the existing prepared navigation replacement. It captures query, search focus and stable
  row/pixel viewport; commit constructs a new frozen action client without rebuilding adjacent Chat routes. The shared coordinator
  retains its account/ready-source/modal/stack checks. Archive also replaces its child when RootVM publishes a new archive folder
  object, so later hydration does not strand the old list. Old child subscriptions/prefetch ownership are released normally.
- Preserve full-width UIKit chrome and current safe-area/search height. Defer replacement/hydration during dragging/deceleration
  or marked input; matching scroll callbacks, query changes, appearance and Root state schedule retries. Independent review caught
  a tracking-only wait with no terminal scroll callback; the final gate excludes tracking-only touches. IME unmark without a query
  event remains a runtime proof gap, not claimed solved.
- Reference: pinned current/pre `ChatListUI/Sources/ChatListController.swift` 98 / 91 retains immutable account context and
  list location. BetterTG adapts this ownership to its existing TDLib `readyClientChanges`, accepted folder hydration and
  `ChatListArchive` model; no new TDLib API, storage format or copied navigation infrastructure.
- Three modified Swift files formatted together; final `build-Debug-20261002-205425-50452-17562.log`: PASS9s, zero warnings.
  Audit Simulator PID `52323`, source `6f72a6b` plus the committed delta: client-restoration, Root list and auth probes pass.
  Actual Archive search retains a nonempty local query and active focus through two Home→foreground cycles. Existing Russian
  hardware-keyboard layout transformed the requested ASCII fixture; the exact resulting query survived unchanged.
- Bounded idb log confirms `Archive client restoration: replacement accepted; search-focus=true` in PID `52323` at21:00:18.
  Screenshots/proofs/command limits: `.build/ui-probe-evidence/astra-a30c-primary`. The temporary agent-created filter was closed.
  No archived chat, message, account, server setting or draft was modified. idb's timeout cleanup emitted an asyncio diagnostic;
  it is not an app/build warning. Populated anchor accuracy, live hydration during dragging, late first-layout and cross-account
  navigation remain unverified; the existing generic coordinator probe is not an actual Archive-controller test.
