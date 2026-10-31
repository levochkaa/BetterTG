# A44a ordinary-chat bubble delivery states — 2026-10-03

- Worker `33b144c` integrated as `753aad9`; DEBUG-only geometry correction `77a6e09`. Add derived Equatable status with
  raw Failed/Pending precedence before any temporary-ID comparison; final outgoing ordinary messages show single/double checks
  from the current source/route watermark. Unknown receipt never claims Read. Canonical first chronological album member supplies
  status, independent of newest-first display representative; promotion/replacement recomputes it. Incoming/broadcast/forum
  final states and final Saved Messages mapping stay excluded; Saved pending/failed remains visible despite TD's outgoing flag.
- `ChatVM` subscribes to scoped outbox updates before a fresh current-client getChat baseline. UUID/revision fences reject late
  reads after accepted updates, including duplicates; source departure terminally retires/cancels receipts. History seeds omit
  derived state. Text/footer/media overlays share the status; accessibility speaks Sending/Failed to send/Delivered/Read rather
  than glyphs. References and pinned TDLib semantics are in the preceding A44 audit; no foreign Telegram infrastructure copied.
- Independent review closed same-ID wrapper publication, stale legacy-failure and queued old-owner risks. Structural snapshots
  reconfigure retained IDs whose wrapper changed. Per-message queued invalidations validate exact current model/wrapper and batch
  a receipt burst into one existing anchor-preserving reconfiguration, avoiding one whole snapshot apply per row.
- Native `-ui-probe-message-delivery`, audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5: PID62893 PASS includes
  revision/source/route retirement, canonical album promotion, pending/final replacement, history seed reset, actual MessageCell
  text/footer/media/VoiceOver, same-cell stable-ID replacement, stale owner rejection and 23 changed wrappers in one native apply.
  Fixed-row adapter offset remains unchanged. It is not whole-ChatVM or self-sizing production-history proof.
- Preserve fixture failures: PID58294 compound assertion failed; diagnostic PID59352 isolated retained-cell=true, Read=true,
  stale callbacks=0, but offset `(0,0)→(0,-62)`. UIWindow had not yet applied its initial automatic safe-area inset. `77a6e09`
  waits for actual window/host/collection layout and settled initial inset before capturing the baseline; no assertion was removed
  and no production anchor code was changed. Native PASS followed on PID62893.
- Same PID62893 actual production navigation through bot and ordinary personal histories: incoming bot messages had no outgoing
  checks; four pre-existing outgoing personal-chat messages displayed double checks and spoken Read. No typing, sending,
  reactions, links or message actions. Only already-read rows were opened. Actual outgoing frames were x8/w386 at y469.6667,
  555.0,654.3333,739.6667 with heights80.3333,94.3333,80.3333,32. They remained identical after Home/foreground:
  ownership released04:57:36.747, restored04:58:39.482, Chat viewport settled/fresh-history starts04:58:39.772 (+04).
  Screenshots inspected before/after; same PID, empty composer and keyboard hidden. This proves existing Read display and
  quiescent source renewal, not a live peer read transition or sending/failure lifecycle. Dynamic media resizing, albums under
  live sends and multi-account operation remain unverified. Local artifacts: `.build/ui-probe-evidence/astra-a44-delivery/`.
- Worker and primary full build logs zero warnings/errors; integration `044543-57615-13161` PASS9s, geometry correction
  `045008-60058-31007` PASS6s, each after one all-changed-Swift formatting invocation. A04 range regression PID58294 also passes
  with the unique-byte-coverage backend. A04 production/probe repair is committed as `7c39a37`.
