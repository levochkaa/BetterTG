# Forum-aware Forward destination slice

- **P0 flow:** pre-Liquid/current forum drill-down behavior from `ChatControllerForwardMessages` and `PeerSelectionController`, adapted
  to UIKit + TDLibKit rather than Telegram controllers/state stores.
- Implemented: source route proof at prepare+delivery; destination chat/topic identity; multi-chat/multi-topic selection; exact cursor
  topic picker/search; closed/manage-topic and per-content eligibility; fail-closed forum discovery; exact forward result validation;
  partial retention; account fences; classic full-width material navigation/search and local selection summaries.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-075614-53821-9609.log`; local selection flow and classic header evidence
  `.build/ui-probe-evidence/forum-forward-topic-plain-final-*`; no Forward/send mutation, PID 54141 alive, Simulator booted.
- Deferred: comment/forward-draft transition, deliberate test-account delivery and all-messages headers.
