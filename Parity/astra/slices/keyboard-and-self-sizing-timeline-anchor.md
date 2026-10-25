# Keyboard and self-sizing timeline anchor slice

- **P1 flow:** Telegram-style `messageId + pixelOffset` retention across viewport/intrinsic-size changes in the inverted UIKit history.
- Implemented: message-cell pre-fit height notification; one coalesced visible-message anchor for autonomous self-sizing; exact anchor/latest
  restoration around single/bulk diffable reconfigure, composer/search/selection/keyboard insets, Dynamic Type and rotation; mutation-depth
  ownership so stale deferred size callbacks cannot overwrite a newer snapshot/inset/rotation anchor; active pan/deceleration remains untouched.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-091301-75604-22504.log`; focused delta-review clean. PID `75942`
  retained `Video message, 0:13` at `{{53,381},{260,260}}` and `chat-date-1787342400` at `{{172,348},{58,22}}` across two
  hierarchy-derived focus attempts (`Δx/y/w/h=0`). Simulator did not present `AXKeyboard`—likely hardware-keyboard state—so the
  non-no-op keyboard-attached transition remains a runtime proof blocker. Evidence: `.build/ui-probe-evidence/timeline-anchor-fresh-*`.
