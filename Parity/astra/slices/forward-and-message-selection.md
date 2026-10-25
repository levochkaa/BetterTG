# Forward and message-selection slice

- **P0 flow:** pre-Liquid/current `ChatMessageSelectionNode`, `ChatMessageSelectionInputPanelNode`,
  `ChatControllerForwardMessages` and `PeerSelectionController` behavior, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: context Select/Forward gates; whole-album direct forwarding; stable selection/reuse/accessibility; classic geometry and
  transition timing; 100-child limit; exact per-child property/content preflight; multi-delete; Saved/main/archive/offline/server
  destination discovery; raw-chat secret/private/group/channel eligibility; multi-recipient progress; sender/caption modes; safe
  nonretryable treatment for unknown partial subsets; account-switch fences before every mutation.
- Proof: `Message forwarding probe: normalized=true, limit=true, options=true, album-atomic=true, multi-recipient=true, account-scoped=true, uikit=true, swiftui=false`.
  Device hierarchy proves `forward-probe-saved-messages` and `forward-probe-design-group` are full-width 402×62 AX controls;
  center taps select both, enable the 66×56 Forward control and produce `Ready: 3 sorted IDs · 2 chats` without a Telegram send.
