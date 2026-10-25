# All-messages forum timeline foundation slice

- **P0/P1 flow:** base forum adjacent-topic runs and jump-free history extension from pre-Liquid/current
  `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift`, adapted to one inverted UIKit collection without Telegram
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: stable `message(id)` / `album(mediaAlbumId)` / `topicHeader(topicID,runStartMessageID)` identities; complete
  projection rebuild for `A,A,B,B,A`; official 34pt centered 22pt topic control with 16pt General/custom/generated icon, one-line title
  and chevron; lazy account/client-fenced `getForumTopic` cache plus `updateForumTopicInfo`; authoritative topic tap; message-only
  read/prefetch/playback/context/selection paths; raw TDLib pagination cursor; cross-page album coalescing; permanent member-delete
  survival; message-window reuse; and visible message + pixel-offset restoration across boundary-header insert/remove/merge.
- Production routing follows live `Chat.viewAsTopics`. Base text/photo/edit/draft and chat-action contexts resolve to discovered General
  or the replied message's exact topic; closed-topic replies fail closed, reply transitions cancel the prior topic action, and the base
  draft key remains `topic:nil`. Voice/video manifests now carry a separate immutable send topic through record/pause/resume/preview,
  relaunch, enqueue, resend and exact record/upload/cancel actions; a newer composer reply is never cleared by an older media draft.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-085723-71772-1312.log`; wrapper/idb launch PID `67526` stayed
  alive and ordinary chats retained full composer controls. `.build/ui-probe-evidence/forum-all-messages-*` records the hierarchy scan;
  no safe `viewAsTopics == false` forum exists in current simulator data, so live header tap remains a data-state blocker. Fresh PID
  `71701` passed `.build/ui-probe-evidence/forum-all-messages-media-destination-*`: voice Ogg/Opus + base-draft/frozen-topic relaunch,
  video send outcome/legacy/thumbnail/tombstone cleanup, and ordered multi-segment video recording trim/thumbnails/frozen-topic handoff.
- Deferred: live all-messages topic-header/pagination/album seam proof on an account with a reachable forum in this mode.
