# Exhaustive MessageContent breadth slice

- **P0 flow:** classic content routing based on the pre-Liquid contact/map/poll/action/animated-sticker nodes and
  `ServiceMessageStrings`, adapted to UIKit + Combine + TDLibKit rather than Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: 104-case catalog; shared summary/caption extraction; audio and document rows plus attachment albums; explicit primary-file
  download/cancel/reconcile and thumbnail-only prefetch; details-first contact card with five vCard lines; actual MapKit snapshots and
  absolute live-location timer; single/multi poll submission, persisted pending state, authoritative result/quiz colors and VoiceOver;
  visibility-gated animated emoji/rolling regular dice with safe resolved fallback; centered service pills; italic unsupported placeholder;
  explicit excluded-product fallbacks; account-captured, generation-safe prefetch.
- Proof: the DEBUG probe instantiates production views with real TDLib model values rather than parallel mock views. Its Documents proof is
  `MessageContent probe: tdlib=1.8.66-022d6020, exhaustive-cases=104, views=file,file,attachmentAlbum,contact,location,location,poll,poll,stickerGlyph,stickerGlyph,service,service, sized=true, poll-actions=poll:0,poll:0,1, action-proof=true, uikit=true, swiftui=false`.
  Device screenshots are under `.build/message-content-final-postbuild-*.png`; Simulator remains booted.
