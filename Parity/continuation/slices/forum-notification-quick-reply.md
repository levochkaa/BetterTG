# Forum notification quick-reply slice

- **P0 flow:** topic-aware notification reply using TDLib `getMessage`, `getForumTopic`, `sendMessage(topicId:)` and `viewMessages`.
- Implemented: exact account requirement; captured-client guards; authoritative message/topic fetch; closed/manage-topic and existing
  chat/payment checks; verified same-topic reply target; exact returned chat/topic assertion; fail-closed lookup behavior.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-080453-55869-29388.log` plus focused source delta-review.
- Deferred: deliberate test-account notification action proof and all-messages history/composer parity.
