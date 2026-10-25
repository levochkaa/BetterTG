# Generic self avatar source slice

- **P1 flow:** Telegram current/pre-Liquid generic self info opened from Saved Messages, explicitly distinct from Settings/My Profile.
- Implemented: self is captured once only when a non-nil account user ID equals the peer. Generic self title remains `Saved Messages`,
  presence is blank, redundant Message is hidden, and Search/Edit remain. `ProfileAvatarView` can render the real self peer file over the
  Saved glyph only for this captured profile context. The explicit image path owns account/client/user identity, waits for the full file
  through that client, uses no global `updateFile` bus, never cancels shared TDLib transport, and suppresses every callback after switch.
- Header source follows effective `User.profilePhoto` then main `UserFullInfo.photo`; self `personalPhoto` is ignored and `publicPhoto`
  never becomes current. Gallery ordering is effective current → distinct normal/history → distinct public last. Raw history offsets stay
  server-owned, extra-role count is separate, and pages insert before public without moving the selected item. Transition to/from the
  header requires both exact photo ID and rendered file ID; otherwise it fades. Main/personal/public role signatures trigger a full-page
  reconcile that preserves a historical selection; reconciliation, pagination and initial open have independent UUID-owned task slots.
  An authoritative empty set closes/resets the pager instead of preserving stale media.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-152230-76740-9666.log`; final upstream/API/task-race review CLEAN.
  PID `74705` exposed the real cat avatar as a 96×96 `Saved Messages profile photo` button, exact `Saved Messages` title, no status and no
  Message action; Search/Edit and shared tabs remained. It opened real `Profile photo, May 10, 2023` with `avatar-gallery-close` and no
  mutation. Final build PID `77080` launched on the still-booted Simulator. Evidence:
  `.build/ui-probe-evidence/profile-self-avatar-source.png` and
  `.build/ui-probe-evidence/profile-self-avatar-gallery.png`.
- Runtime blocker/deferred: this account exposes one current profile-photo item, so >100 pagination, distinct public fallback, live role
  replacement, authoritative empty close and concurrent request invalidation are source-reviewed/build-proved rather than live-mutated.
