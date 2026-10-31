# Checkpoint

- Active continuation: `codex/parity-continuation` in worktree `31df/BetterTG`. The complete first media/parity
  history through `37fb759` and all 44 continuation commits through `5e6f5a0` are retained, including member tags.
  The integration merges `ce5015d`, which contains local `main` at `1476556` and TDLibKit 2.0.0.
- Native compatibility preserves account/topic-scoped composer and media drafts, profile permissions, gallery actions and
  persistent FFmpeg sessions. Legacy archive adapters preserve formatted text, quotes, replies and all MessageTopic variants;
  native value equality preserves reaction/avatar change detection. Generated aliases exclude application-owned types such as
  `ChatLocation`. Chat open/close transitions are serialized per account/client/chat.
- Timeline invariants: raw TDLib pagination owns the cursor; complete pages are hydrated without skipping an unconsumed item;
  canonical album/date/topic identity and visible message + pixel-offset restoration remain in the continuation.
- Verification: Xcode 26.6 / iOS 26.5 build `.build/logs/xcodebuild/build-Debug-20260905-162801-7759-9727.log` has no warnings.
  PID `5795` passed fresh legacy draft coding, Ogg/Opus, account/topic-isolated voice drafts, frozen-topic video send/recording
  drafts and persistent VP9/Opus range playback probes. Results are app Documents probe files; UI evidence is under
  `.build/ui-probe-evidence/parity-merge-20260905/`.
- UI navigation passed chats → chat → profile → Members → profile → shared photo gallery → profile → chat → chats.
  Member rows enter the tag editor; the available account's permission-denial path is expected. Authorized tag Save/remove
  and other server mutations remain unverified. The later feature checkpoint remains promote/demote/remove and admin-rights
  editing, independent of the existing tag flow.
- Fixed the inherited profile header-width defect: centered labels now use the full header content width, consistent with
  Telegram upstream `PeerInfoHeaderNode`'s screen-width-based text layout. On iPhone 17 Pro / iOS 26.5, a long group title
  changed from x=154 / 94×54.67 pt (split and truncated) to x=20 / 362×26.67 pt (complete on one line); avatar remains 96×96 pt.
  Evidence: `03-profile` versus `14-fixed-profile` PNG/JSON in the UI evidence directory above. At that checkpoint, PID `8105`
  was running on the corrected profile; action buttons and media grid were unobscured.
- Generator cleanup: `td.py` moved to `script/td.py`; the wrapper, repository-root calculation, generated header and both
  agent documents use the new path. The final warning-free build exercised the relocated generator with the existing package cache.
