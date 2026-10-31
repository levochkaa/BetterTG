# A22 delayed viewport authority — 2026-10-02

- `19dc395` binds automatic latest/anchor compensation to a one-shot geometry ticket. Structural snapshot, single/bulk reconfigure,
  rotation, deferred self-sizing and reply-quote expansion consume only the newest current ticket. Capture and completion both
  reject active tracking/drag/deceleration; gesture invalidation remains effective after scrolling ends. Explicit message/latest
  navigation retires old automatic tickets. Revoked Chat ownership cannot restore an old viewport.
- Quote expansion resolves the stable item ID after apply, not its captured index path. Independent inset/highlight changes retire
  pending compensation; inset work caused by a completion's own synchronous layout stays in that compensation. Initial inset pinning
  no longer overrides active scrolling. Existing message IDs, history/cursors, send transitions and A30 restored-viewport contract remain.
- Reference: pinned pre-Liquid `TelegramUI/Sources/ChatHistoryListNode.swift` 4229–4238 stationary-item transactions;
  `Display/Source/ListView.swift` 297–304 tracking state,2124–2194 deferred geometry,3180 tracking-aware inset repair.
  No upstream UI infrastructure copied; no TDLib schema/API changes. Independent four-file source review found no introduced blocker.
- All four changed Swift files formatted together; final `build-Debug-20261002-201821-1578-13580.log`: PASS8s, zero warnings.
  Audit Simulator source `19dc395`, PID `2570`: `-ui-probe-viewport-authority`, Chat state, composer restoration/entities pass.
  Policy probe verifies stale/repeated ticket rejection, current scroll/context gates, 1,000 superseding revisions and fresh work after
  invalidation. It does not exercise UICollectionView diffable completion timing or emulate a real drag.
- Actual own Saved Messages opens, scrolls to earlier history, stays at that settled position across later observation and returns to
  latest using its visible button; composer remains available. Screenshots and probe outputs: `.build/ui-probe-evidence/astra-a22-primary`.
  The first chat screenshot caught the push transition; use the settled/after-scroll/after-idle/returned-latest captures for UI evidence.
  No messages, drafts, account settings or links were changed. Controlled prepend/resize/rotation/keyboard races, programmatic-scroll
  animation overlap and exact pixel-offset instrumentation remain unverified; this is not complete timeline parity.
- Additional actual keyboard smoke, 2026-10-03 03:41–03:47: installed code `ddfa897` (documentation HEAD `3da0f1b`),
  audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, same PID `59144`.
  Saved Messages was scrolled away from latest and allowed to settle; tapping the empty composer showed the Russian software
  keyboard, and tapping blank history dismissed it. Two pre-keyboard AX samples and the shown/hidden samples retain the same
  fully visible row rectangles: privacy-safe label hashes `946a11dcc510` at `(8,139.3333,386,46)` and `5169c6a01ad7` at
  `(8,229.3333,386,191)`. Composer y moved `796.6667→487.6667→796.6667`, with text length zero throughout.
  Screenshots inspected: `.build/ui-probe-evidence/astra-a22-keyboard/{scrolled-first,keyboard-shown,keyboard-hidden}.png`.
  These are AX label hashes, not TD message IDs; this proves only the settled nonlatest empty-composer show/hide sequence.
  No typing, sends, links or message actions. Interactive dismissal, simultaneous prepend/resize, rotation, send flights and
  nonempty composer remain unverified. No Swift change was needed for this bounded check.
  Documentation build `build-Debug-20261003-034905-77575-16672.log`: PASS5s, complete log zero warnings/errors.
- `b552043` (worker `152c848`, reviewed tree `44a14cfc`) adds opt-in `-ui-probe-viewport-completion` to an actual already-open
  Saved Messages controller. No mock rows/VM or history writes: unchanged production snapshot, held exact native completion,
  stable original item ID and geometry, matched control and ended delegate-drag cases. Probe motion suppresses its own willDisplay
  read-receipt/history demand; real entry/scroll remains normal UI. Interference is SKIP, invariant failure is FAIL.
  Review rejected an initial diagnostic global-invalidate cleanup; final cleanup consumes only its captured ticket before releasing
  held completion and cannot retire a newer real capture/quote ticket. No production authority algorithm was changed.
- Single SwiftFormat0/2; integrated build `build-Debug-20261003-123000-86500-18926.log`: PASS13s, full log zero warnings/errors.
  Audit59EB535C/iOS26.5 PID88609: first run expired before the manual scroll (12:32:54 SKIP, no assertion failure). Reopened actual
  Saved Messages and scrolled once: fresh run96B73C04 report12:34:25+04 PASS. Control offset475.6667→539.6667→475.6667,
  stable-ID pixel354.3333→290.3333→354.3333. Ended delegate drag retains539.6667/pixel290.3333 after the old completion.
  Native/release counts2/2, restoration counts1 total, each layout depth1→0, cleanup returns initial viewport and holds no closure.
  `astra-a22-completion/after-pass.png` inspected. Actual inserted older rows, physical drag during apply, resize/keyboard/rotation
  overlap and interrupted cleanup transport are not established by this bounded unchanged-snapshot test.
- Supplementary PID93318 reports12:36:16/19: Chat restoration state and composer pass; viewport helper FAILS A39 animated
  target/quote settlement after resize. Standalone rerun PID316, fresh report12:40:56 PASS, with unchanged build/source. Preserve
  the first failure: its cause is unresolved; concurrent fixtures are not a proven cause. This is not a full clean runtime-suite claim.
