# UIKit peer profile and shared-media slice

- **P1 flow:** pre-Liquid/current peer-info header, pane and open-message behavior from `PeerInfoScreen.swift`,
  `PeerInfoHeaderNode.swift`, `PeerInfoPaneContainerNode.swift` and `PeerInfoScreenOpenMessage.swift`, adapted to UIKit + Combine +
  TDLibKit without Telegram infrastructure.
- Implemented: chat title/avatar entry; user/bot/self/basic-group/supergroup/channel identity; full-info bio/description,
  username/phone/member details; Message/Search actions; one scrollable Dynamic Type header; Media/Files/Links/Audio tabs; exact current
  `MessageTopic` query scope and open-in-chat route; stable deduplicated pagination; empty and later-page retry without losing the cursor;
  account/client fencing; cancellable grid thumbnail download with redisplay restart; accessibility labels and intrinsic action height.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-105649-495-22414.log`; focused source/delta review clean. Runtime PID
  `840` exposes Profile/Back, exactly one `4 members`, 56.67pt intrinsic Message/Search actions, the four-tab group, 12 visible Media
  tiles, `No shared files`, real Link rows and a real `.m4a` Audio row. The exact Media→Files→Links→Audio path remains alive after fixing
  UIKit diffable snapshot reentrancy, and Back returns to the group chat. Evidence is under
  `.build/ui-probe-evidence/profile-shared-media-*`; no media or server mutation was selected.
- Deferred at this slice (see subsequent profile/gallery slices): avatar/video header history and fullscreen entry; edit/member/admin
  controls; shared-media selection/actions; live metadata reconciliation; gallery caption, gesture, rotation and complete
  save/forward/delete/open-in-chat/video-control parity.
