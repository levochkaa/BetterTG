# A49c2 frozen timeline transactions — 2026-10-03

- P1, `caff71e` (worker `7e16c1c`, reviewed tree `bac0ab6f`): all five production snapshot producers share one active
  transaction and a coalesced intent buffer. Provider rows retain exact canonical identity, immutable render values, client/source,
  header and selection inputs through exact native completion. Materialization and new inline players remain lazy; live action,
  navigation and prefetch lookup stay separate. Raw album membership must be committed before navigation/send settlement.
- Preserve A22 interaction epochs, A44 owner invalidation, A50 all-row selection exit, temporary/final aliases and the140ms
  deletion deadline. Tombstone-owned bindings survive intermediate commits. Same-album reappearance first commits removal,
  then queues fresh membership without turning stale recovery into post-drag restoration. Duplicate/ownerless receipts release
  only the matching batch; pending/finishing states block premature navigation/send/client settlement.
- Committed visible-row acknowledgement deduplicates current visible raw IDs and checks the attached active scene/route.
  Context previews may load history but cannot acknowledge reads. Background/read-retry/player ownership changes have source
  review, not live transport proof. No TDLib API change; pinned TDLibKit remains `1.5.2-tdlib-1.8.66-022d6020`.
- Telegram references: official master `6ad963e5`, pre-Liquid `8e7e5fe`,
  `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`4197–4241 (raw-member correlation and transaction-owned history);
  pre-Liquid `submodules/TelegramUI/Sources/ChatController.swift`7372–7384 (all history selection updates). No infrastructure imported.
- Worker compile failures `145001`/`145414` (actor isolation/explicit captures/type inference) and weak-mutation warnings
  `145605` were corrected, not suppressed. Review withdrew earlier approvals for deletion-lease carryover, same-album liveness
  and mixed-epoch recovery; final worker `151204-36307-16904` PASS9s/fullzero. Primary joint SwiftFormat0/9 and
  `151812-44934-6936` PASS23s/fullzero; exact reviewed tree integrated without other Swift changes.
- First native scheduler probe, Audit59EB535C/iOS26.5 PID48152/container `3F87B0C4-06F0-4748-A8BF-6D9C6F987646`,
  report15:19:13+04 FAIL: deleting-cell presentation changed. Diagnostic-only `09af63d` (worker `ee0f2ab`, reviewed tree
  `d638b735`), format0/9/build `152429-60083-15376` PASS12s/fullzero, preserves the assertion. PID62822/container
  `0539F196-6964-4174-B1C0-9C134447DEB6`, report15:25:35 FAIL confirms exact same cell/binding/lease, reuse0,
  interaction disabled; alpha0.375/translation(8,-3) survive provider return, but UIKit resets cell alpha1/identity by native
  receipt. Production also animates these cell attributes: an inner presentation-layer repair is required, not a weaker oracle.
- Same `caff71e`: delivery/action regression PID49199/container `D31762BA-315B-4FC8-8946-C4DA59FB09CF`, report15:20:15 PASS.
  Standalone viewport-authority PID50146/container `E157EB3B-DCCB-45ED-91FE-D5E081F2B63D`, report15:21:10 FAIL:
  A39 animated target/quote did not settle after resize. Driver/probe are byte-unchanged from `039df63` and do not instantiate
  ChatView. Historical failure remains unresolved; this repeat disproves any claim that only combined runs can fail.
- Actual Saved Messages A22 PID51820/container `7E07B2CE-3C0E-483C-9110-AD462FC19784`, report15:23:35 PASS:
  exact native/releases2/2, depth1→0; control offset483.3333→547.3333→483.3333, anchor pixel346.6667→282.6667→346.6667;
  ended synthetic delegate drag retains547.3333/pixel282.6667. One physical scroll entered the exercise; IDs were unchanged.
  Real prepend/media resize/keyboard/physical overlap remain unverified. No sends/deletes/forwards or host focus activation.
- `6ae99ac` (worker `c1ef72a`, reviewed tree `d0a54bb4`) moves deletion opacity/slide/scale into MessageCell.contentView,
  composing its permanent timeline flip. Cell/descendant AX and interaction are disabled during deletion; configure/unavailable/
  reuse reset only the owned inner layer, preserving rowStack swipe/selection and externally extracted menu content.
  Worker joint9-file format/build `153256-73686-3111` PASS10s/fullzero; primary format0/9/build `153501-78488-29638`
  PASS12s/fullzero. Assertions now measure the actual owned presentation, including same-cell normal configure and animation reset.
- Audit59EB535C/iOS26.5 PID79368/container `B9291225-072C-42EF-883E-0A471DF8472C`, report15:35:36 PASS: production
  scheduler/native MessageCell, all five coalesced demands, exact/duplicate/ownerless receipts and depth, frozen values/actions,
  committed raw album members, stale restoration rejection, both same-album deletion/reappearance schedules and AX/reset.
  Late provider/native receipt preserve inner opacity/transform and exact binding without reuse. Actual ChatView producer races,
  physical gestures, live client switch,140ms delete timing and actual timeline media-player ownership remain unverified; RPC/sends0.
- Same final production `6ae99ac`, PID79903/container `585489CE-C989-4009-8687-A6065E83554B`, report15:36:23 PASS:
  existing delivery/render/action/poll/touch/source/receipt native regressions. Earlier media-reveal regression at `09af63d`,
  PID69532/container `78A0D689-DDC4-4EB4-9F6A-E7C481D2B0A3`, report15:29:29 PASS with isolated native media/backend;
  it does not prove real timeline gestures, TDLib transport or active system PiP.
- Same final PID79903 actual Saved A22 report15:38:06 PASS: native/releases2/2, depth1→0, stable IDs unchanged.
  Control offset488.6667→552.6667→488.6667, anchor pixel341.3333→277.3333→341.3333; ended synthetic delegate drag
  retains552.6667/pixel277.3333. Ordinary Select→Cancel and Select→tap sole selected row both remove all visible selectors
  and restore the empty composer. Screenshots `c2-final-viewport`, `c2-final-selected`, `c2-final-cancel`,
  `c2-final-deselect-before`, `c2-final-deselect-clean` inspected under `.build/ui-probe-evidence/astra-a49b-actions/`.
  Root screenshots contain private previews and must stay local. No sends/deletes/forwards/reactions/votes/profile/account edits;
  ordinary navigation may acknowledge history through the app's normal read path. The injected probes themselves issue no RPCs.
- Next bounded slice: add passive A39 completion/failure-reason receipts (outcome, post-result visibility, offset error,
  commands/native ends and deadline versus correction budget). Confirm or reject the source candidate where a late layout
  offset change clears `receivedEnd` and leaves no future end to resume checks. Keep current deadline/centering assertions;
  then add an exact event-order regression and repair only a measured defect. Driver/probe do not use the ChatView scheduler.
  Further A49 coverage: actual queued producer overlap, prepend/keyboard/media resize, committed-read lifecycle and current
  inline-player ownership. Native fixture success is not proof of these whole-controller/server paths.
- Final checkpoint build `154717-90533-2969` PASS9s, full1385-line log has no warnings/errors; AGENTS/CLAUDE agree,
  production/dependency VLC and forbidden UI/infrastructure marker scan is empty. Source checkpoint `6ae99ac`; only this
  parity record changed after that build. Simulator remains booted in Saved Messages, selection exited; no host focus activation.
