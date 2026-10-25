# UIKit emoji/sticker/GIF composer slice

- **P0 flow:** pre-Liquid/current emoji/sticker/GIF input panel behavior, adapted to a UIKit page sheet and TDLib-native
  `getStickers`, `getSavedAnimations`, `InputMessageSticker` and `InputMessageAnimation`.
- Implemented: Emoji/Stickers/GIF segmented grid; debounced search and mode-generation cancellation; account/client/chat fencing before
  loads and selection; installed regular sticker query with every Premium sticker excluded; saved-GIF filtering; exact picker-cell AX;
  TGS/WebP/WebM reuse with offscreen pause and GIF thumbnail cancel/restart; repeated emoji insertion with debounced route draft; exact
  other-message permission, General/reply topic and returned-destination assertion. Sticker sends preserve typed text while clearing the
  accepted reply through the captured draft topic with generation-fenced retry; GIF caption clears safely; both use serialized sends and
  the insertion-flight protocol. No Premium/Stars/custom-emoji results are offered.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102014-91617-3187.log`; focused source/delta review clean. Runtime
  PID `90585` proved the UIKit sheet, exact three segments, 64 enabled emoji buttons, 16 non-Premium sticker buttons, 16 saved-GIF
  buttons, offscreen-safe navigation and Done return. Evidence: `.build/ui-probe-evidence/composer-media-picker-final-*`; no
  emoji/sticker/GIF was selected or sent.
