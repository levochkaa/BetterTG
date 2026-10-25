# Forum topic browsing slice

- **P0 flow:** pre-Liquid/current `ChatListNodeLocation`, `ChatListNodeEntries`, `ChatListItem`, `ChatControllerContentData` and
  `ChatControllerLoadDisplayNode`, adapted to UIKit + Combine + TDLibKit without Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: account/client/chat/topic route identity; captured-client ref-counted open lease; exact topic cursors/order/hidden/search;
  update refetch and transient retention; explicit topic history/search/read acknowledgement; target-message topic resolution; classic
  UIKit rows with General/custom-emoji icons, pin/closed/draft/unread variants, Dynamic Type, VoiceOver and offscreen animation pause;
  stable-ID reconfiguration; fail-closed push/forward; VM-level read-only barriers with non-mutating content access preserved.
- Proof: warning-free build log `.build/logs/xcodebuild/build-Debug-20260831-062650-32938-29366.log`; device hierarchy/screenshot files
  `.build/ui-probe-evidence/forum-topics-*`; `[1,42,77]`, hidden 99 absent, AX tap `(201,262)`, status
  `Opened topic 42 · Read-only`, PID 31980 alive.
- Deferred: all-messages topic-run headers, topic composer/writes/durable drafts, topic forwarding selection, topic actions/mutations,
  General hidden toggle/admin controls, unread navigation and live server pagination/mutation smoke.
