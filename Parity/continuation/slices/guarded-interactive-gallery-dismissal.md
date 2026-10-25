# Guarded interactive gallery dismissal slice

- **P1 flow:** Telegram current/pre-Liquid down-swipe gallery dismissal, adapted to the existing exact-source UIKit animator through
  `UIPercentDrivenInteractiveTransition` without importing Telegram gesture/transition infrastructure.
- Implemented: one-finger, positive-y, 1.2× direction lock; exact centered-page requirement; minimum photo zoom with no zoom bounce or
  deceleration; horizontal pager cooperation; temporary pan/pinch suspension only after begin; touch exclusion for footer, every
  `UIControl`, visible video controls and Retry; active seek/PiP/start/stop/retention rejection. Progress is translation-driven; 28% or
  900pt/s finishes, otherwise cancel restores chrome, modal AX isolation, pager/zoom gestures and pending page/delete updates. Playback
  owners release only from the animator's completed commit. Account switch force-finishes the interaction and pops the profile from the
  transition completion; an unexpected cancel uses a terminal nonanimated fallback instead of leaving an invalid gallery visible.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-114920-12706-5954.log`; final delta review CLEAN. PID `12991` proved a
  slow 70pt/1s down-pan cancels with only gallery AX and restored `gallery-close`/`1 of 30`/`gallery-share`; a 450pt/0.4s down-pan finishes
  at Profile with the exact 131×131 source tile; horizontal swipe still reaches `2 of 30`; up-swipe remains in gallery. No Share or
  server mutation occurred; Simulator remains booted.
- Deferred: deliberate zoomed-photo, live seek, active PiP and external account-switch gesture rejection on capable/runtime states.
