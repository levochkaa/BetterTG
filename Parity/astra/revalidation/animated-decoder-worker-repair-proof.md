# Animated decoder worker repair proof — 2026-10-02

- Scope: A07 only. Preserve first-frame fallback, existing frame timing/cache behavior and C-handle ownership. A native-free
  initializer creates the actor; `prepare`, frame reads/resets and `isolated deinit` run on its dedicated serial executor.
  Setup cancellation/generation/path/asset checks and frame decoder identity reject stale completion, including same-path reuse.
  A05/A06 account/download ownership and A08 timing are intentionally unchanged and remain open.
- Worker commit `c5642bc5b7b75210a467519b8e314a1cbaa4c801` was reviewed and cherry-picked as `956e0ee`.
  Only `FFmpegAnimatedVideo.swift` and one DEBUG entry in `BetterTGApp.swift` changed. Worker SwiftFormat covered both files;
  warning-free build log is preserved in the primary checkout at
  `.build/logs/xcodebuild/worker-A07-build-Debug-20261002-143909-89115-12760.log`.
- Worker run on isolated Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS 26.5, PID `92196`, remained alive for 51 seconds
  on production login. Preserved evidence: `.build/ui-probe-evidence/astra-worker-a07/animation-worker-probe.txt`,
  `astra-animation-login.png` and `astra-animation-login-hierarchy.json` in that directory.
- Primary integration: one SwiftFormat call covered all four Swift files changed during the audit repairs (`0/4` changed).
  `./build.sh build` passed without warnings at `956e0ee`; log
  `.build/logs/xcodebuild/build-Debug-20261002-144312-3881-1967.log`. Independent delta review found no blocker.
- `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B -- -media-probe-animation-worker`
  launched PID `4465`. Fresh container `E53CD086-9694-41C8-89CD-F27E033BC0A3` output was written at
  `2026-10-02 14:43:47 +0400`; idb pulled it into
  `.build/ui-probe-evidence/astra-integrated-animation-worker/animation-worker-probe.txt`.
  Both runs report actual create/read/reset/destroy off-main, main-release/worker-destroy, delayed-setup cancellation,
  same-path reuse fencing, replacement readiness, preserved first frame and exactly-once teardown; five native reads.
- Integrated screenshot/hierarchy `astra-integrated-animation-login{.png,-hierarchy.json}` show the live production 2FA screen,
  not a chat/sticker flow. The user subsequently reported logging into the open Simulator; no credentials were entered by the agent.
  On resume, inspect current authorization/reachable chats before selecting authenticated smoke. This user update does not close
  B01 for the original database or prove sticker playback. The later explicit continuous-work request authorizes further slices.
