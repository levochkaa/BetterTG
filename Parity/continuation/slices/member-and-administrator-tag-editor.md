# Member and administrator tag editor slice

- **P1 flow:** current `PeerInfoData.swift`, `PeerInfoScreenOpenMember.swift`, `ChatParticipantRightsScreen.swift` and TelegramCore
  `Ranks.swift` rank editing, compared with pre-Liquid `ChannelAdminController.swift`, adapted as an independent UIKit + TDLibKit tag
  operation rather than an administrator-rights mutation.
- TDLib boundary: captured-client `getChat` plus parallel actor/target `getChatMember` reads before presentation and again immediately
  before one awaited `setChatMemberTag`. Basic groups and non-channel supergroups are accepted; inactive targets and channels fail closed.
  Self editing requires fresh `ChatPermissions.canEditTag`. Editing another user requires creator status or fresh
  `AdministratorRights.canManageTags`; another creator is protected, and a non-creator may edit an administrator only when
  `canBeEdited`. The target tag must still equal the captured baseline before the write, preventing a stale editor from overwriting a
  concurrent change.
- UIKit editor preserves the current tag verbatim, counts at most 16 Swift characters, rejects controls and graphic emoji, accepts empty
  to remove the tag, and keeps transport errors visible without optimistic canonical state. Successful writes explicitly schedule an
  authoritative member-list reload instead of relying on the bot-only `updateChatMember` delivery contract. Account/client changes cancel
  preparation or saving and disable stale controls.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-153759-82885-28094.log`; final focused delta review CLEAN. Runtime PID
  `83599` exposed all three real member rows as enabled buttons with disclosure chevrons and the `Shows member tag controls` hint. Tapping
  self `лева` performed the fresh authority reads and produced `Can't Edit Tag` / `You no longer have permission to edit this member's
  tag.`, then OK returned to Members. Screenshots:
  `.build/ui-probe-evidence/member-tag-smoke-members.png` and
  `.build/ui-probe-evidence/member-tag-smoke-permission-denied.png`. No text was edited, Save was never pressed and no Telegram mutation
  occurred; Simulator remains booted.
- Runtime blocker/deferred: this live account cannot edit a tag, so an authorized Save/remove and post-success refetch are not exercised
  against the server. Promotion, demotion, removal and administrator-right editors remain the next bounded profile-management gap.
