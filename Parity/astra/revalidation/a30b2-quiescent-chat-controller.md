# A30b2 quiescent Chat controller — 2026-10-02

- `9abead4` (worker `7f98a52`) enables the existing terminal navigation replacement for ordinary Chat. Captured target-client
  metadata, account/chat/topic and retained-route checks precede synchronous composer/history ownership transfer. Imports, marked
  text, modal/context menus, gestures, capture/send operations and timeline transitions defer replacement. Paste/Photos/camera/files
  register import ownership before asynchronous work; same-account results can finish on a retained old-client route.
- Selection, focus and mic/video mode transfer separately. The retired text view resigns only its own responder; the new controller
  restores one message ID + pixel offset after snapshot, appearance, layout and keyboard settlement, then starts history freshness.
  User scroll/input invalidates this initial anchor. A22 general timeline epochs and active capture restoration are not repaired here.
- Primary follow-up `5ac2810` adds the missing explicit retry after emoji-picker Done or invalid-context dismissal. UIKit's
  interactive presentation delegate does not cover that programmatic completion. Foundation probe labels now state that those
  probes do not exercise controller navigation. A DEBUG-only, content-free log identifies actual viewport settlement.
- References: pinned current `ChatInterfaceState/Sources/ChatInterfaceState.swift` 232–270 and pre-Liquid 514–531, distinct
  compose/reply/edit/history/media state and message-index-relative offset. TDLib captured-client `getChat/getForumTopic/getMessage`,
  chat/thread history and accepted ready/update source; no new server mutation or storage schema.
- Primary builds: `.build/logs/xcodebuild/build-Debug-20261002-190318-62891-1540.log` (12s), combined voice build
  `build-Debug-20261002-190401-63298-26208.log` (11s), final picker fix `build-Debug-20261002-192208-71024-31859.log` (7s), all
  zero warnings after each slice's single SwiftFormat invocation. Sandbox-only CoreSimulator access failed; authorized wrapper retry
  succeeded without resetting data. Source review also corrected first-responder retirement before integration.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro / iOS 26.5: source `f1721d0`, PID `64668`, actual
  Saved Messages retained latest and settled non-latest viewport plus empty-composer caret after Home→foreground. The initial
  non-latest screenshot preceded deceleration and is not anchor proof; the repeated settled pair is visually consistent, without an
  automated pixel-error measurement. Software keyboard was hidden by the hardware-keyboard setup.
- At `5ac2810`, PID `71481`, open emoji-picker survived Home→foreground; Done returned the actual chat. At 19:26:46 the same
  process logged `Chat client restoration: viewport settled; fresh history starts`. No emoji selection, text input, attachment,
  send or account switch. Screenshots and state probe: `.build/ui-probe-evidence/astra-a30b2-controller-primary`; worker notes are
  separate. Chat state/composer foundation and A06 authority/demand probes pass; their isolated transports are not network proof.
- Pending: interrupted real provider imports, nonempty edit/reply/attachment transfer, software-keyboard transitions, active voice/video,
  ForumTopics/Archive/editors, live account switches and delayed server-history races. Full A30 remains partial.
