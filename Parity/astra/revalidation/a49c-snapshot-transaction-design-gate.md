# A49c snapshot transaction design gate — 2026-10-03

- Source `1d67d4d`: all five producers must move together: structural snapshot, single/bulk reconfigure, highlight (including
  DEBUG branch) and quote. Highlight currently has no depth/completion lifecycle. Delete's140ms deadline protects only structural
  applies; no deleting-ID filter prevents a reconfigure from restoring alpha/interaction. This is a confirmed ownership gap,
  not grounds to change TDLib pagination or live action/navigation lookup.
- Planned bounded replacement: provider-only frozen render values, exact canonical wrapper identity separate from render clone,
  full sender/reply/forward/album/formatted/properties/reactions/unread/sendFailed/pin/quote/delivery/mutation state and exact client.
  Do not reuse client-restoration seed semantics, which intentionally drop delivery/mutation state. Freeze header info and cell
  selection/highlight/layout inputs as well. Actions compare current canonical state against rendered values, never against the clone.
- One active UUID batch, committed/outgoing render rows and one coalesced pending demand buffer; pending stores intent/IDs,
  not stale NSDiffable snapshots. Build membership/frozen values at dispatch, retain outgoing rows through exact completion,
  reject duplicate callbacks and balance each depth owner even after source retirement. Exclude fading deletion IDs from
  reconfigure, respect the existing deadline, and preserve A44 owner invalidation and temporary→final aliases.
- Preserve A22: stamp a pending buffer with a separate interaction-invalidation revision, never refresh that stamp during
  coalescing. Stale demand may update content but cannot mint a new automatic restoration ticket after an ended drag.
  Keep an explicit finishing/busy phase through completion/depth release/drain; navigation, restored viewport, send flights and
  client replacement must see pending work and cannot settle in the gap between applies. Initial unloaded/no-window hydration
  remains allowed; obsolete sources cannot dispatch. This design is reviewed, not implemented or runtime-proven.
- First standalone prerequisite A49c1: immutable render value used as the existing action-authority baseline, with canonical
  identity kept separate; exact/lazy render-only materialization and mutation-isolation probes. Existing predicate semantics,
  client-restoration seeds, provider and all five apply paths remain unchanged in this prerequisite. The following integration
  must switch provider/scheduler together, including old bound-cell fade preservation, deleting-ID tombstones through exact
  removal completion, and committed raw-member checks before send/navigation settlement (an added album member reuses its ID).
- A49c1 `eaf8c3d` (worker `4609e9f`, reviewed tree `6ab765ce`) captures all14 message-render fields as values and lazily creates
  detached renderer adapters with exact private delivery state, mutation flags, explicit nil reactions and empty unread state.
  Existing action authority now stores this value baseline separately from canonical wrapper identity; current production callers
  keep existing capture timing and admission semantics. Client-restoration seeds and provider/snapshot paths are unchanged.
- Worker build `140810-18467-16598` PASS13s/fullzero; primary joint SwiftFormat0/9/build `141710-32677-17015` PASS14s/fullzero.
  Audit59EB535C/iOS26.5 PID35594, fresh container `2A3C5EC4-9438-40E6-B6CB-4528C450FF1D`, report14:18:11 PASS. Extended
  `ChatMessageActionAuthorityProbe.verifyRenderValues` runs before the existing report's success: same-wrapper album promotion,
  sender/metadata/formatted/properties/reaction/read/mutation changes leave captured values and exact materialization unchanged;
  clone mutations stay isolated; old baseline fails, fresh baseline+canonical passes, clone cannot acquire canonical authority.
  All prior delivery/A49/A44 native cases pass. Source+native prerequisite proof does not establish frozen production rendering.
- Fresh pre-integration baseline at clean `564d545` (production `eaf8c3d`, product from `141942-39748-21216`): standalone
  viewport-authority PID67824/container `86434DC1-9554-4BA7-8BBD-768A533512E0`, report14:34:47+04 PASS. Native A39
  animation/estimated-height resize/convergence passes; the earlier combined-run failure remains unexplained, not superseded.
- Actual Saved Messages baseline, wrapper `-ui-probe-viewport-completion`, Audit59EB535C/iOS26.5 PID77750/container
  `07C30E00-16D2-410F-9DCB-326F7756FCA7`, report14:43:58+04 PASS. Control offset498.6667→562.6667→498.6667 and
  stable-ID pixel331.3333→267.3333→331.3333; ended synthetic delegate drag retains562.6667/pixel267.3333. Native/releases2/2,
  depth1→0, original anchor restored in cleanup. `c2-baseline-viewport.png` inspected. One physical scroll entered the fixture;
  concurrent physical drag/history insertion/resize/keyboard remain unverified. No send/delete/forward or host focus activation.
  These are checks of the committed prerequisite, not proof of the in-progress scheduler.
