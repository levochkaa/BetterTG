# Link-resolution progress — 2026-10-30

Scope: the link-spinner UI pass and replacement cleanup, from `9d8869a6` on
`t3/refresh-goal-prompt`. Implementation is in this audit's commit.

## Reference and changes

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:
`submodules/OverlayStatusController/Sources/OverlayStatusController.swift` and
`Impl/Sources/OverlayStatusControllerImpl/{ProgressWindow,ProgressSpinnerView}.m`.

The loading overlay remains blur, not Liquid Glass. BetterTG's thick system material and system spoked
indicator are replaced by the reference's light/dark blur, light-only `0xf4f4f4` tint at 75%, and 48 pt
three-quarter arc. Its stroke is 4 pt with round ends, radius 19, `0x5a5a5a` in light / white in dark;
it rotates −2π every 0.75 s. The 100 pt square, 20 pt corners, 0.6→1 scale and 0.3 s fade remain.
The existing public UIKit spring is retained; this audit does not prove its exact equivalence to Telegram's
private curve option. The 250 ms delay remains BetterTG's approximation of the cache/network boundary.

All eleven router task assignments now use `TelegramLinkResolution`. Previously replacing a URL resolution
with a direct user/chat/profile/message action only cancelled its Task; a noncooperative TDLib request could
leave the old touch-blocking overlay until its response. Replacement now cancels the task and removes its
overlay immediately, including an overlay already fading. Delayed show is terminal after finish, and old
completion/removal callbacks cannot remove a replacement. Normal completion and tap-cancel fade out, then
stop the arc animation and remove the view. Accessible activation/Escape call the same cancellation path.
A cancellation guard before link classification also prevents the debug slow-link delay from submitting a
request after cancellation. Routing, account checks and TDLib operations are otherwise unchanged.

## Verification

SwiftFormat covered all four changed Swift files. Final `./build.sh build` passed in 24 s; complete log
`build-Debug-20261030-004152-65856-11475.log` has zero warnings/errors. Installed and built debug dylibs
matched SHA-256 `3575f68b4a6e4424c30b4aaa1774c0136a75a147e89776e91f16194e14932e5e`.
The first build exposed two warnings only in the verifier (deprecated window initializer and weak variable
mutability); both were fixed using the scene initializer and a weak constant, without suppression.

iPhone 17 Pro Simulator / iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`:

- New `-ui-probe-link-progress`: the production owner and view run against local response continuations
  that deliberately ignore cancellation until released. At `2026-10-29T20:42:33Z`, the verifier passed fast
  completion/no attachment, delayed show, replacement while the old request is pending, late old response,
  old-view release, accessible cancellation, replacement during cancel fade, completion during appearance,
  and cancel before the delay. Its attachment counter detects even a brief show before removal.
- Existing `-ui-probe-telegram-links` passed at `20:42:29Z`: URL classification and mention dispatch remain
  intact. Both results were read from fresh Documents probe files after installing the final build.
- Visible fixture: dark/light arc and blur; outside-square tap cancels, and the eventual response remains
  ignored. Normal completion removes progress. Replacement with another slow operation and with a direct
  operation were exercised; reduced video frames confirm rotation and a single replacement square.
- Real router: with the existing `-ui-probe-slow-links`, `bettertg://settings/devices` opened Devices and
  left no overlay. The tool's open call took 2.77 s, beyond the two-second delay, so the planned cancel tap
  instead opened a session's read-only details, which were closed. This is completion proof only; no session
  was terminated and no account setting changed. Normal launch restored the persisted appearance and removed
  all probe flags.
- Captured fixture launch console contains no Auto Layout conflicts or fatal/precondition failures. It does
  not cover every later gesture.

Evidence: `/tmp/bettertg-link-progress.mp4`, `bettertg-link-progress-replace-frames.jpg`,
`bettertg-link-progress-dark.png`, `bettertg-link-progress-light.png`,
`bettertg-link-progress-cancelled.png`, `bettertg-link-progress-replaced-finished.png`,
`bettertg-link-progress-router.png`, `bettertg-link-progress-console.log`.

## Limits and next

Server latency/failure, cancellation of an actual outstanding TDLib request, account switch while resolving,
VoiceOver gestures, rotation, iPad, iOS 27 and physical devices were not exercised. The noncooperative-request
proof is local and deterministic; it does not claim cancellation of server work. No invites, messages,
sessions or persistent preferences changed.

Next UI pass: network-usage segmented control, contact-selection send bar and sticker-settings toolbar.
Invite pull-down/progress morph and earlier device/menu/readiness gaps remain recorded separately.
