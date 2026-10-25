# Profile member, administrator and edit controls slice

- **P1 flow:** current/pre-Liquid peer-info member/admin panes and creator/administrator edit gates, adapted to UIKit diffable tables and
  TDLibKit without Telegram account or list infrastructure.
- Implemented: a separate intrinsic management row with Members, Admins and permission-gated Edit. Basic groups use the complete
  `BasicGroupFullInfo.members`; supergroups/channels expose Members only under `canGetMembers` and advance pagination by raw
  `ChatMembers.members.count`; Administrators use `getChatAdministrators` independently of hidden-member access. Stable local
  user/chat IDs preserve server order and unresolved fallbacks; one queued resolver batches same-ID reconfiguration through a serialized
  diffable apply; Dynamic Type and VoiceOver include title, role and presence. Live `updateChatMember`/full-info changes debounce a fresh
  authoritative load while retaining the first visible ID and pixel offset. Later-page failures remain visible in a table footer with
  explicit Retry. Account changes cancel child work and atomically remove the complete navigation suffix at the owning Profile.
- Edit captures account/user/client/chat identity. Cached creator or administrator `canChangeInfo` controls visibility, while every chat
  submit calls `getChatMember` for that captured user immediately before `setChatTitle`/`setChatDescription`. Self edit uses
  `setName`/`setBio`. Only changed fields are sent in sequence; successful first operations update the retry baseline, and a second-operation
  failure reports partial success without optimistic canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-132517-34076-25539.log`; final focused audit has no remaining API/model,
  pagination, diffable or account-lifetime finding after the atomic suffix fix. PID `33583` exposes a separate 176×56.67 Members/Admins
  row on the real three-member basic group; Members resolves exact `<member>, Owner`, `<member>, Member · online`, `лева, Member`, while
  Administrators independently resolves `<member>, Owner`. Screenshots:
  `.build/ui-probe-evidence/profile-management-controls.png` and
  `.build/ui-probe-evidence/profile-administrators-controls.png`. Edit was correctly absent for this non-admin account; no Save or other
  server mutation was performed.
- Runtime blocker/deferred: a safely reachable self/owned test profile was not mutated, so Edit form writes and live permission revocation
  are source-reviewed/build-proved rather than server-proved. Member promotion/removal/admin-right editors remain a later management gap.
