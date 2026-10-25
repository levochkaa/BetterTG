# Probe sweep — 2026-10-12

Repeat on the merged build `52c8ae5` (localization merge): 86 of 91 probes report a pass; `draft-coding` passes in the app's tmp folder, and the four observation probes need live UI as above.

All 91 launch-argument probes ran on iPhone 18 Pro (iOS 27.0) against the merged build through `./build.sh run
--skip-build`, one launch per probe. Probe repairs are in `1d29328`: probes that borrow the active client wait for the
asynchronous TDLibKit 2 account bootstrap, test entities stay within `Int32`, and probes follow the merged semantic,
localized and forward-picker APIs. After the repairs and F12/F13 every probe that reports by itself passes, including
`vod-resource-loader` (progressive playback before completion, controls, offline retry, no full download) and
`video-note-lifecycle` (about 2 minutes). Four probes only observe live UI and wrote nothing in an unattended launch:
`folder-selector-content`, `profile-header-layout`, `viewport-completion` and `message-navigation`; they are
exercised by hand:

- `viewport-completion` passed in Saved Messages after scrolling away from both edges: the real ChatView kept its
  snapshot IDs, and the held native completion restored the stable-ID pixel offset; a synthetic delegate drag rejected
  the old restoration. Physical gestures, history insertion, media resize and keyboard overlap stay unverified.
- `message-navigation`: tapping a test reply's quote in Saved Messages scrolled to the loaded target with an
  animated scroll and settled 0.2 pt from the command offset with unchanged snapshot IDs, then highlighted the target.
  The test reply was deleted afterwards.
- `profile-header-layout` passed on the Saved Messages profile (labels fill the width, 96 pt avatar). The shared
  media gallery opened from the grid, paged 1 → 3 of 6 and closed with the swipe-down dismissal back to the grid.
- `folder-selector-content`: 815 candidates, 35 empty raw titles (all deleted accounts), no empty cell text and no
  title mismatches after F14. The same check found F16.
