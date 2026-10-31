# A44b2b exact per-topic receipts in all-messages history — 2026-10-03

- Worker `fef1b1f` integrated as `bc5f234`. Each existing reader entry owns `ChatDeliveryReceiptState` for its exact positive
  forum topic. Its receipt ticket starts with the same metadata request and consumes the raw response before metadata admission;
  no second RPC or queue is added. Direct scoped scalar updates change receipts even when metadata is absent or failed.
  Identical receipts advance the revision fence without publishing an unchanged state. Prune/retire revokes both owners before
  notifying current wrappers; re-demand starts with no inherited watermark. Cached/restored display metadata grants no receipt.
- ChatVM uses the canonical raw album member's chat/topic, not the newest display representative. Unknown current exact-topic
  watermark shows Delivered; nil/thread/saved/direct/foreign-chat and broadcast final states are excluded. Raw Pending/Failed
  precedence remains unchanged. A separate receipt callback derives only matching current wrappers, independent of metadata
  equality; existing Equatable publication and stable-ID batching repaint cells without scroll intent or per-row reads.
- Review found two additional initialization gaps: restored history assignment bypasses didSet, and new supergroup eligibility
  originally derived status before demand sync. Both now synchronize first, as does messages.didSet. A small b2a follow-up moves
  restored video metadata demand after the async reply lookup and current-source guard, immediately before installing its draft;
  the queued reconciliation can no longer prune that still-unassigned context. These ChatVM ordering paths are source-reviewed.
- Native PID34441 on `bc5f234`, same audit Simulator59EB535C-3610-41A2-AB68-53A9467DC24B/iOS26.5: both reports fresh06:41:21
  (+04) PASS. Reader probe covers distinct topic watermarks, direct update before/after failed metadata, duplicate update versus
  late baseline, wrong raw scopes while valid control topics remain Read, nil-cache pruning/re-demand and source retirement.
  Existing b2a queue/concurrency/lifetime cases also pass. No live TDLib RPCs or global source mutation were injected.
- MessageCell native adapter uses the production reader/projection and current raw wrappers: topic11 changes only its canonical
  album row to Read while topic12 stays Delivered, preserving the actual cell and fixed-row collection offset. Same stable-ID
  album promotion switches to topic12/Delivered; callbacks from the removed wrapper cannot repaint its replacement. Pending,
  failure, final-ID replacement, seed reset and retirement pass. Ordinary/explicit-topic/native batching regressions remain PASS.
  The adapter does not execute the entire ChatVM, live source subscription, self-sizing history or peer-read transport.
- Five changed Swift files formatted together. Primary064029-33247-16763 PASS14s; exact final worker063739-30512-24107 PASS11s,
  full logs zero warnings/errors. Independent immutable review PASS. Proof files:
  `.build/ui-probe-evidence/astra-a44-all-messages/forum-topic-receipts-probe.txt` and `message-delivery-b2b-probe.txt`.
  Safe live all-messages availability remains blocked as above; no server preference was changed to manufacture a fixture.
