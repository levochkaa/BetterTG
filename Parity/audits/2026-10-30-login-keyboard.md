# Login keyboard layout — 2026-10-30

Scope: the keyboard-covered form recorded by the login-bar audit, from `b36df4d2` on
`t3/refresh-goal-prompt`. Implementation is in this audit's commit.

## Reference and change

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`:
`submodules/AuthorizationUI/Sources/AuthorizationSequencePasswordEntryControllerNode.swift`,
`AuthorizationSequencePhoneEntryControllerNode.swift`, `AuthorizationSequenceSignUpControllerNode.swift`,
and `submodules/AuthorizationUtils/Sources/AuthorizationLayout.swift`.
They subtract the keyboard from available height, pin Continue 24 pt above it and centre the remaining form.

Previously BetterTG centred every control in the full safe area. The password keyboard obscured part of
Continue and all of Forgot password. Continue now sits in a separate footer, 24 pt above UIKit's keyboard guide
(the bottom safe area when no keyboard is present). Its width is capped at Telegram's 430−48 pt.

The existing form controls stay in a stack, centred in the space between the bar and footer. A scroll container
grows when the content no longer fits; it preserves field sizes and allows secondary actions to scroll into view.
Content scrolls under the common bar. Focus/viewport changes reveal the active field within the area below that
bar, with 12 pt clearance. Stage changes reset the scroll position with the existing credential clearing.
Hidden Continue collapses its footer without a conflicting required minimum height. Auth ownership and requests
are unchanged.

## Build and final proof

SwiftFormat covered all three changed Swift files. `./build.sh build` passed in 40 s; complete log
`build-Debug-20261030-002303-34358-15433.log` contains zero warnings and errors. Installed and built debug dylibs
matched SHA-256 `92bfc278c7b6529889279fc0eb120b64fdedc39c1efb9b77f5f66639e83b254e`.

iPhone 17 Pro Simulator / iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`. The existing isolated login
fixture gains `-login-probe-form phone|code|password|registration|qr` to hide its control overlay, and
`-login-probe-large-text` changes only its own preferred content-size trait.

- Final password fixture: field and Forgot password fully visible; Continue y=467…515 with the keyboard
  beginning at y=539. Forgot password opened the existing no-recovery-email alert; OK restored the keyboard/form.
- Final registration at accessibility XXXL: both 64 pt fields remain intact; Continue grows to 77.33 pt and
  stays 24 pt above the keyboard. Scrolling reaches the complete multiline Terms of Service control while
  Continue remains fixed. Its alert opens; returning restores second-field focus at y=344…408 below the bar.
- The isolated auth ownership probe passed on the final build at `2026-10-29T20:23:53Z`: source/stage isolation,
  duplicate submissions, stale completions, revoke/deinit, account rebind, denied states and recovery stages.
- Normal launch restored. No account, real credential, server authentication or persistent preference changed.

Final evidence: `/tmp/bettertg-login-layout-final-password.png`, `bettertg-login-layout-final-terms.png`,
`bettertg-login-layout-final-focus-restored.png`.

## Earlier build checks and verifier correction

On `7f111e2c0440509cbaa382befd1998abf9ea3b1dd86a09e9a30c15885632fcc8`, phone and code were inspected with
their number pads: Continue and secondary actions stayed above the keyboard. A fixture password submission
completed locally; hiding the keyboard moved Continue back to y=768…816. The captured password launch console
had no constraint conflicts or fatal errors. These checks preceded the bar-aware focus reveal adjustment.

On `7a00fa2babff79817c57873ccf4a503b9e857575bc4b3ea57d48087206c86c88`, QR mode showed the whole code and
phone option with no Continue/keyboard and no constraint conflicts or fatal errors in its launch console.
That build has the final production code; the subsequent edit only fixes the debug verifier's async waits.
Evidence: `/tmp/bettertg-login-layout-phone.png`, `bettertg-login-layout-code.png`,
`bettertg-login-layout-dismissed.png`, `bettertg-login-layout-qr.png`, `bettertg-login-layout-console.log`,
`bettertg-login-layout-qr-console.log`.

The auth probe first reported `recovery code not checked`, then passed on an unchanged installed binary.
Its recovery sequence assumed one main-queue hop also drained Swift Tasks. Those positive async checks now wait
for their actual request/completion condition, bounded to one second; assertions and production auth code remain.
This removes that unsupported ordering assumption rather than accepting a green retry as sufficient proof.

## Limits and next

Server authentication, email/recovery UI layouts, iPad/floating keyboards, rotation, RTL and physical devices
remain unverified. This does not claim full accessibility parity or Telegram's complete intro visuals.
A long drag-to-dismiss gesture was rejected by the tool's keyboard-clipped viewport; the advised shorter retry
was accepted but did not dismiss the keyboard. Interactive keyboard-dismiss timing is not proven by this slice.
Next: invite-link sheet and the remaining spinner/network/contact/sticker chrome from `goal.md`.
