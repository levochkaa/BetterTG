# A30h member-tag editor renewal: repair contract — 2026-10-03

- Source `bc5f234`, primary and independent review: `PeerProfileControlsViewControllers.swift`314–326 pushes the tag editor
  above Members. `PeerProfileMembersRestoration.swift`145–151 requires Members itself topmost, so Profile's retention gate
  (`PeerProfileViewController.swift`234–242) fails; synchronous client-change handling1017–1021 reaches1095–1123 and drops
  Profile/Members/Tag together. The tag editor1170–1188 captures one immutable old client and has no renewed edit session.
  This is a concrete source-proved P1, not a claim that the live account's authorized editor was exercised.
- Bounded change: hold only the exact attached adjacent Profile→Members→Tag chain for the same account and actor, preserving
  the existing editor, text/selection/marked input and visible errors. Keep stale parents quarantined and defer their replacement
  until editor closes; do not widen generic Members.canRetain or Profile replacement eligibility. Existing parent restoration
  resumes afterward. Reuse/extend the existing PeerProfileEditSession rather than replacing the navigation architecture.
- One explicit tag Save gets a current Ready endpoint and repeats getChat plus actor/target getChatMember, permissions and
  captured-baseline conflict checks before setChatMemberTag. Preserve empty-tag removal and validation. Source/actor/detached
  changes must prevent dispatch; a possibly dispatched write becomes uncertain with no automatic retry. A delayed ACK must not
  pop over newer typing. No live tag/rights mutation is authorized by this smoke; use controlled endpoints for those boundaries.
- References: current `6ad963e` `TelegramUI/Components/ChatParticipantRightsScreen/Sources/ChatParticipantRightsScreen.swift`
  63–64,250–274,502–516 and `TelegramCore/Sources/TelegramEngine/Peers/Ranks.swift`15–42 preserve rank edit intent and
  account-owned explicit commit; pre-Liquid `8e7e5f` `PeerInfoUI/Sources/ChannelAdminController.swift`
  922–933,1150–1155,1304–1311 owns updated rank/focus. These do not prove Telegram behavior under TDLib client recreation.
  TDLib `022d6020`: getChat/getChatMember/setChatMemberTag and canEditTag/canManageTags; preserve the existing authority matrix.
- Planned proof: actual UIKit editor with exact-chain retention and controlled edit endpoints; repeated same-account epochs,
  raw text/selection, predispatch cancellation, postdispatch uncertainty/no replay, new typing versus delayed result and Back
  release. Existing profile/member probes must pass. Live authorized editing remains unavailable unless naturally permitted;
  no synthetic production route or server changes to create the fixture.
