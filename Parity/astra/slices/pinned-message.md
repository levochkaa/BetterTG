# Pinned message slice

- **P0 flow:** pre-Liquid/current `ChatInterfaceStateContextMenus`, `ChatControllerLoadDisplayNode`,
  `ChatPinnedMessageTitlePanelNode` and `ChatControllerNavigateToMessage`, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: exact Saved/private/group/channel pin modes; fresh `canBePinned` preflight; one serialized chat mutation; optimistic
  newest-pin state with authoritative revision rollback fences; account/client/generation guards before and after TDLib; initial and
  refreshed `getChatPinnedMessage`; 404-only clearing; cache/permanent-delete/edit/content/isPinned reconciliation; direct-message/forum/
  topic/album/service/sending gates; shared spoiler-safe thumbnail extraction; 50pt full-width blur banner; separate Open/Hide AX controls;
  local hidden-ID token; newer-pin resurfacing; selection/search suppression; stale-animation rejection; inverted-history inset stability.
- Proof: `Pinned message probe: modes=true, visibility=true, 404-only-clear=true, newest-only=true, banner-height=50, local-hide=true, navigation=true, uikit=true, swiftui=false`.
- Deferred: nearest-visible pin rotation, pinned-only list/pagination, admin unpin undo, older-pin warning details, topic-scoped pins and
  deliberate live server mutation proof.
