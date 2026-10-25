# Message reactions slice

- **P0 flow:** pre-Liquid/current `ReactionButtonListComponent`, `ChatMessageReactionsFooterContentNode`,
  `ChatMessageBubbleItemNode` and `ChatController` toggle/restriction behavior, adapted without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: representative-bubble standard/custom reaction rendering; Telegram count-minus-own-selection sorting; exact 30/20pt
  geometry and 6pt wrapping; chosen/unread styling; reusable accessibility; account-keyed custom-emoji sticker cache; offscreen
  animation pause; zero-state context picker; authoritative per-message availability; Premium/paid exclusion; maximum-count-safe
  optimistic add/remove with rollback; chosen removal under restrictions; normal-client interaction/unread reconciliation; live
  chat permission/max updates; account-switch fences; chat/topic reaction-read acknowledgement; read-only topic and ephemeral mutation gating.
- Proof: `Message reaction probe: reducer=true, remove=true, add=true, max-count=true, unread=true, paid-excluded=true, wrapping-chips=true, uikit=true, swiftui=false`.
  Device hierarchy proves the exact two-row frames/gaps and paid omission. Fresh center taps produce
  `👍: 2, Not selected` and `❤️: 1201, Selected` while PID 11956 remains running.
- Deferred: custom-emoji origination grid, reactor list/avatars, removal animation, forum-topic identity and live server mutation proof.
