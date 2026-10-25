# Context-menu gestures through Xcode device interaction — 2026-10-12

Real multi-touch sequences (`mt`) on iPhone 18 Pro iOS 27.0, build after `5a0e1b3`, in Saved Messages:
hold 1.0 s then scrub to Copy and lift ran Copy (pasteboard changed) and closed the menu; lifting the opening finger
in place kept the menu open with nothing highlighted; scrubbing past the 10 pt hysteresis and lifting outside the menu
kept it open and ran nothing; tapping Select entered selection; a chat-row hold scrubbed to Add to Folder opened it;
the gallery More menu grew out of the button and closed back into it, with luminance rising and falling smoothly in a
60 fps recording (F26 noted). Reduce Motion at runtime (10-17, Simulator `com.apple.Accessibility ReduceMotionEnabled`
on, app relaunched, then restored): the story probe reported `reduce-motion=true`; gallery More opened without the morph,
the ••• button stayed visible and the menu grew in below it (60 fps `rm.mp4`); a 1.2 s hold on a chat row only darkened
it, its text at the same pixels until the menu opened (`rmrow.mp4`), where without Reduce Motion the same hold moved the
row's text outward by about 1.5 pt, the 8 pt growth (`row.mp4`). Recordings are in `/tmp/morph-ev`.
