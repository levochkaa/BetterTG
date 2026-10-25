# Real profile avatar gallery slice

- **P1 flow:** current/pre-Liquid `PeerInfoAvatarListNode` → `AvatarGalleryController`, adapted to UIKit and native TDLibKit models rather
  than synthetic timeline messages.
- Implemented: header 96pt image/button AX only when a real effective/full photo exists; a true placeholder remains image-only. User/bot
  payload preserves effective/personal/normal/history/trailing-public roles with stable `ChatPhoto.id` dedupe, keeps raw history offset
  independent of extra role entries, inserts later 100-photo pages before public fallback and exposes footer Retry. Group/channel use the
  only available TDLib source, `BasicGroupFullInfo.photo` / `SupergroupFullInfo.photo`; `ChatPhotoInfo.big` is a static fallback only and
  never fabricates an animation. A separate UIKit pager keeps stable photo IDs/current page through rotation, exact-animates the whole
  circular header only for the current item and fades historical items. Captured-client synchronous JPEG/MP4 requests have per-file
  generations and no global update bus; 96MB/cost-limited decoded cache; static image remains until `AVPlayerLayer` ready; animation seeks
  to `mainFrameTimestamp`, loops muted only central, pauses/resets offscreen; nested pan activates only above 1× while pinch/double-tap
  remains available. Late network completions require current account, visible/top profile and no competing presentation.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-124706-24968-7861.log`; final source/delta review CLEAN. Runtime PID
  `24630` exposes `<group> profile photo` as 96×96 button, opens real `Profile photo, Mar 19, 2026` in the modal pager with plain
  `avatar-gallery-close`, then restores the exact 96×96 source. Screenshot:
  `.build/ui-probe-evidence/profile-avatar-gallery-final.png`; no mutation occurred.
- Blockers/deferred: current safe group has one static photo, so user >100 pagination, animated avatar loop and zoom gestures are not
  runtime-proved. TDLib cancellation is global per client/file; without a cross-consumer lease coordinator, offscreen deliberately
  cancels only local await/decode/playback work and lets active transport finish into TDLib cache rather than cancel another consumer.
