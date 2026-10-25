# Unified fullscreen gallery chrome slice

- **P1/P2 flow:** current/pre-Liquid gallery single-tap chrome and video-control coordination, adapted to UIKit recognizers without
  importing Telegram transition/gesture infrastructure.
- Implemented: controller-owned `chromeIsVisible`; edge-to-edge pager behind a full-width safe-area blur overlay; photo single tap
  dynamically waits for nested double-tap zoom; controls/retry/seek touches are excluded; selected video disables its private tap and
  reports controls visibility/auto-hide through its playback owner to the same footer/status state; page/reuse/dismiss/PiP bindings are
  explicit. VoiceOver can never leave Close/Share hidden, hidden footer leaves AX, Reduce Motion is honored, and accessibility Escape
  closes. Video controls stay exactly above the 50pt footer plus bottom safe area instead of being obscured by the overlay.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-113041-8640-9218.log`; final delta review CLEAN. PID `8944` proved
  photo chrome `visible→hidden→visible` (`402×874` media when hidden), video single-tap exposing seek/back/play/forward/mute/rate plus
  `gallery-close`/`2 of 30`/`gallery-share`, playing auto-hide removing both control groups from AX, and Close returning to Profile.
  Screenshot: `.build/ui-probe-evidence/profile-gallery-unified-video-controls.png`; no Share or server mutation occurred.
- Deferred: deliberate double-tap/pinch and VoiceOver-status runtime toggles.
