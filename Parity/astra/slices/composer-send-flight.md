# Composer send-flight slice

- **P0 flow:** pre-Liquid Telegram composer source-to-message insertion transition, adapted to real UIKit snapshots and TDLib temporary
  IDs without Telegram transition infrastructure.
- Implemented: synchronous capture of visible reply, formatted text, selected-photo strip, caption, active voice/video preview and
  retry-button sources; one serialized composer text/media send; temporary→success/failure ID aliases before or after acceptance;
  canonical album/message target lookup; 320ms staggered frame/corner/opacity flight into the real visible bubble; bounded offscreen
  fallback; five-second/deinit/account cleanup. Voice direct/trim-preview/promotion/retry and video recorder/retry paths bind runtime-only
  transition tokens to their durable draft IDs, accept exact returned message IDs, and cancel retained/interrupted/discarded failures.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-093342-80738-1901.log`; focused source/delta review clean. No deliberate
  test-account send was performed, so the visible flight remains a mutation-gated runtime proof gap.
