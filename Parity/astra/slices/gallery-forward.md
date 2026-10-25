# Gallery Forward slice

- **P1 flow:** Telegram current/pre-Liquid gallery `MessageGroup` sharing, adapted to BetterTG's existing UIKit
  `ForwardMessagesViewController`, forum topic picker, comment state and `MessageForwardingService` rather than a parallel delivery path.
- Implemented: Forward is serialized with Open/Save/Share and captures account/client/chat/topic/selected ID before any await. A fresh
  `getMessage` validates the source. Non-album media proceeds as one message. For an album, no loaded gallery row is trusted: exact
  base/forum/direct-messages/Saved/thread history APIs request expanding 20/40/100 windows around the selected ID. A group is accepted
  only when both adjacent nonmatching boundaries are present or Telegram's 10-item cap is reached. History transport failures advance to
  the next window and finally degrade to selected-only; cancellation propagates immediately. Fresh IDs retain exact topic and server
  order semantics through `MessageForwardRequest`.
- Complete groups show an explicit `This Item` versus `All N Items` action sheet, so a protected/unavailable sibling never prevents the
  user from trying the selected item. The chosen request enters the production destination search, secret-chat forced-copy rules, forum
  topic drill-down, formatted comment, sender/caption options, partial-delivery handling and exact account fences. Gallery playback pauses
  only while the full-screen picker is visible and resumes on Cancel; successful delivery reports recipient count in the existing footer.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-142756-56092-20725.log`; final Telegram/TDLib delta review CLEAN.
  PID `54892` exposed the real `Forward to` picker with search, destination eligibility, Add a comment, `1 message` and disabled Forward
  before selection; Cancel returned to the exact `1 of 1688` gallery with Close/More/Share intact. Final build PID `57324` launched on the
  still-booted Simulator. Evidence: `.build/ui-probe-evidence/gallery-forward-picker.png`; no destination was selected and no
  `forwardMessages` mutation occurred.
- Runtime blocker/deferred: the reachable selected photo has no album, so the item/all choice and every topic-history variant are
  source-reviewed/build-proved rather than live-data-proved. Deliberate delivery remains a test-account mutation gap.
