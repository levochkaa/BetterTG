# Writable explicit forum topic slice

- **P0 flow:** pre-Liquid/current closed-topic input panel, topic placeholder, text/attachment/media recording, activity and draft
  semantics from `ChatInterfaceStateInputPanels`, `ChatTextInputPanelNode`, `ChatController`, `ChatControllerOpenAttachmentMenu` and
  `ChatControllerMediaRecording`, adapted to UIKit + Combine + TDLibKit without Telegram infrastructure.
- Implemented: immutable send context; exact topic for text/photo/album/voice/video/action/draft; returned-topic assertions; same-topic
  replies; content-specific and live closed-topic authority; dirty/stale draft fences; generation-safe clear retries; edit preservation;
  partial-album retention; exact-location reactions/polls/delete/forward source; writable/restricted UIKit composer states and topic
  placeholder. Base forum history is now handled by the separate all-messages resolver above.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-073123-48367-634.log`; non-mutating real-topic route and production
  composer evidence `.build/ui-probe-evidence/forum-topic-write-final-*`; PID 48686 alive, Simulator booted.
- Deferred: forward comment, all-messages General-or-reply resolver/run
  headers, deliberate test-account send/draft mutation, topic-scoped pinned banner and remaining attachment types.
