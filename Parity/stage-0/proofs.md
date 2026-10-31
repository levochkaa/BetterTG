# Stage 0 proofs — 2026-10-12

- Build: `./build.sh build`, Xcode 27.0, full app recompile after M3 (334 Swift files) with 0 warnings
  (`.build/logs/xcodebuild/build-Debug-20261012-034326-50800-5062.log`); incremental builds after `9a7cccc` with 0
  warnings. M2 built separately on Xcode 26.6 with 0 warnings.
- Simulator smoke on `ea64c34` plus F1, iPhone 18 Pro, iOS 27.0 (`46AD65F9-D204-47F1-A765-B74D8322BC28`), real account; test
  writes only in Saved Messages and the private test forum `BetterTG test`:
  chat list and folder switching with unread badges and the lens; open chat; send text; send a photo from the library;
  gallery paging, More menu and swipe dismissal; voice hold-to-send and playback (microphone prompt first rejects a
  too-short clip as expected); video-note mode switch and recorder, which reports a capture failure because the
  Simulator has no camera; Saved Messages profile with Media/Files tabs and profile gallery; message context menu with the
  reaction strip; Forward to and the pending-forward block; forum topic list with hidden search; rich message, formulas
  and caller-owned spoiler reveal.
- Limits: no physical device, camera, system PiP or 120 Hz proof; no video-note playback (no reachable note); text
  spoilers in ordinary messages, multi-account switching and probes were not run after the merge.
