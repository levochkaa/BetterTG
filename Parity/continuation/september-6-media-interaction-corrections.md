# September 6 media interaction corrections

Gallery dismissal now drags full-size media vertically in either direction. Chrome and background
fade with distance (Telegram's 50pt/80pt ranges); releasing animates from the current position into
the validated source. Source views use alpha instead of `isHidden`, preserving arranged-view
geometry. Open in Chat prepares the destination first and starts the highlight only after landing.
The shared-media viewer is presented by the navigation controller so removing the profile beneath
it does not short-circuit dismissal. Highlights fade in/out as an overlay without rebuilding cells.

The photo/video pager spans the chat, with account/topic-bound history loading in both directions.
Thumbnails contain only the current message album, disappear for standalone media, interpolate
width during paging, and select the centered item while scrubbing. Photos and albums reach their
bubble edges, with separate caption/metadata padding and continuous photo-caption joins. GIFs loop
inline without opening the viewer. Live Photo uses Telegram's two original gallery icons, aligned
with Back; message/reply summaries distinguish Live Photo from Photo.

Keyboard attachment now updates the visible composer blur's bottom corners. Voice/video recording
retains the input row height. Video-note recording overlays the chat navigation bar; inline playback
hides central controls while playing and removes the progress ring when playback ends.

A physical iPhone reproduced the double-camera-switch failure: the final video was 6.0367s while
audio ended at 5.9725s. Capture now freezes video and drains delayed microphone buffers through its
last frame before closing audio. Strict media validation remains enabled. The same front/back/front
probe passed with a 6.07s square recording; it only creates and deletes a local clip, never sends it.
Reports are in `.build/ui-probe-evidence/video-note-double-switch/`.

Simulator recordings under `.build/ui-probe-evidence/gallery-composer-20260906/` and
`.build/ui-probe-evidence/media-navigation-20260906/` cover source-return geometry, keyboard corners,
recording height and cancellation, captions/replies, Live Photo controls, both Open in Chat routes,
post-transition highlight fading, album scrubbing, and paging beyond an album with older-history
loading. The final shared-media return/highlight proof is `profile-final/06-profile-return.mp4`.
An existing suitable GIF was not available for this UI pass; inline GIF playback is build-verified.
No message was sent by these checks. Final simulator and device builds
`build-Debug-20260906-170646-15353-6396.log` and `build-Debug-20260906-170755-16779-25227.log`
passed without warnings; the device was relaunched normally after the capture probe.
