# Fullscreen gallery Open in Chat slice

- **P1 flow:** Telegram current/pre-Liquid gallery context action `Open in Chat`, adapted to the existing UIKit footer and BetterTG
  timeline-window loader without Telegram gallery/navigation infrastructure.
- Implemented: a plain 52×50 ellipsis control alongside unchanged Close/Share on the full-width classic blur footer. The action exists
  only when the presenting route supplies a captured account/client/source location and completion. Tap freezes a Sendable
  chat/message/topic identity, disables the control with progress and calls `getMessage` through the captured client. Completion checks
  action generation, selected ID, account/client, returned identity and exact topic for scoped profiles; base-chat routes intentionally
  accept any forum topic. A permanent delete, page change or account invalidation cancels quietly. Success forces a fade instead of the
  reverse tile transition and retains a separate navigation generation through dismissal; the completion rechecks account/client/context
  before invoking Profile or Chat. Profile pops only after modal dismissal; Chat uses its existing `prepareMessageWindow` path when the
  target is outside the loaded timeline. Secret-chat navigation needs no send/delete/save permission and remains allowed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-134050-43746-25199.log`; final focused delta review CLEAN. PID `44134`
  exposed exact footer frames `Close 4×790 52×50`, `More actions 294×790 52×50`, `Share 346×790 52×50` and the sole UIKit menu action
  `Open in Chat`. Selecting the first profile item (`1 of 1688`) completed gallery fade and profile removal, returning to
  the source group chat with the exact `Photo, 13:31` bubble visible. Evidence:
  `.build/ui-probe-evidence/gallery-open-in-chat-menu.png` and
  `.build/ui-probe-evidence/gallery-open-in-chat-result.png`; no Telegram mutation occurred.
- Runtime blocker/deferred: the safe smoke did not switch accounts or delete the selected message during the subsecond dismissal window;
  both races are generation-fenced and source-reviewed. Forward and Delete were subsequently recorded in their own slices below.
