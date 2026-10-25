# Date and topic boundary slice

- **P1 flow:** pre-Liquid/current `ChatMessageItemImpl.swift` date/topic merge break and `ChatMessageDateHeader.swift` 34pt service
  header ordering, adapted to stable heterogeneous UIKit diffable items.
- Implemented: calendar-start stable IDs; 34pt inverted rows with centered 22pt localized pills; Today/Yesterday/year-aware labels and
  header accessibility; one separator per day in ordinary and forum histories; exact visual date→topic→message ordering on simultaneous
  boundaries; no duplicate topic header at midnight; message-only read/prefetch/selection/playback; structural pixel-anchor reuse; and
  significant-time/locale snapshot reconfiguration so cached Today labels and timezone-derived identities cannot go stale.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-090344-73347-22038.log`; runtime hierarchy/screenshot evidence is
  `.build/ui-probe-evidence/date-headers-*`. Fresh PID `73694` exposes `chat-date-1787860800` (`Aug 28`, 58.67×22) and
  `chat-date-1788033600` (`Yesterday`, 76.67×22); 6pt row insets plus existing 5pt message gaps prove the exact 34pt row with zero
  overlap, while the enabled composer remains at y=796.67.
