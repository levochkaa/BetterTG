# Reply, quote and forward provenance slice

- **P0 flow:** pre-Liquid/current `ChatMessageReplyInfoNode`, `ChatMessageForwardInfoNode` and bubble tap semantics, adapted without
  AsyncDisplayKit/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: cross-chat/ID-zero/story/unavailable fallbacks; forwarded target author override; `ForwardSource` chat-first display and
  message→chat→sender navigation; hidden-author static state; thumbnails including round video notes; 1-line ordinary and 5/50-line manual
  quote layout; source/context accessibility and bubble custom actions; exact quote range search/highlight; external reply input and every
  media draft restoration path; account/client guards; cache/permanent-delete and stale-generation fences.
- Proof: `Message metadata probe: inline=true, unknown-chat=true, source-priority=true, expand-then-navigate=true, forward-navigate=true, external-input=true, utf16-quote=true, highlight=true, uikit=true, swiftui=false`.
  Screenshots are `.build/message-metadata-final-*.png`; Simulator remains booted.
