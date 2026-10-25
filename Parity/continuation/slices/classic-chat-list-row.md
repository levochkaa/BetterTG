# Classic chat list row slice

- **P2/P1 flow:** pre-Liquid `ChatListItem` presentation applied to existing UIKit chat/folder data and actions.
- Implemented: full-width 76pt rows; 60pt avatar at x=10; content/separator x=80; pinned/normal/highlight backgrounds; title/preview/date;
  pending/failed/delivered/read state; unread/muted/marked-unread/pin accessories; capped Dynamic Type; full-state VoiceOver; full-row context
  extraction and tap target. Existing diffable stable IDs, prefetch, search, gestures and TDLib actions remain unchanged.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-063859-35683-18833.log`; exact frame/tap evidence
  `.build/ui-probe-evidence/classic-chat-rows-*`; first tap opens Saved Messages; PID 35152 alive; Simulator booted.
- Deferred: typing/action preview, verified/scam/status/story adornments, archive reveal gestures and full account fencing for list mutations.
