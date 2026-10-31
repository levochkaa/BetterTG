# A21c timed secret video-note hold authority — 2026-10-02

- `bd8723c` (worker `46772f7`) replaces global open/file authority and persistent reveal with frozen account/client/message,
  one configuration token and one token per hold. Scoped content/edit/delete/file updates and client/lifecycle changes revoke
  playback. Release, move-out, cancellation, reuse and offscreen teardown remove the player and concealed pixels synchronously.
- A supported incoming timed note validates fresh metadata, obtains its complete file, revalidates, awaits captured-client
  `openMessageContent`, then requires fresh positive finite `selfDestructIn` before player admission. Monotonic expiry includes
  metadata latency conservatively and cannot extend across holds. Late ACK/error/seek/display callbacks cannot authorize another
  hold or configuration. Cancellation does not retract an RPC already dispatched to TDLib.
- Immediate/view-once, missing/invalid timer and outgoing secret forms remain unavailable before this view's I/O. This is not
  a global TDLib/prefetch no-download policy. No temporary copied-file lease, screenshot prevention, secret gallery/export/PiP
  or photo/video/animation hold is added. Ordinary video-note play/pause remains supported.
- Primary review found ordinary thumbnails admitted before a rejected backend. `9844135` (worker `1a3c9d4`) gates thumbnail
  and minithumbnail admission and revokes off-window playback even when a detached view remains retained.
- References: pinned TDLib `MessagesManager.cpp` 9303–9324,10199–10223,10329–10352,16968–16994,20641–20642; generated
  `MessageVideoNote`, `Message.selfDestructIn` and `openMessageContent`. Zero remaining duration may mean not started. Immediate
  expiry can remove files during open. Pinned current/pre `GalleryData.swift` 317–319 / 267–269 and
  `GalleryUI/Sources/SecretMediaPreviewController.swift` 519–551,590–597 / 517–549,588–595 use a separate protected viewer
  and pre-consumption file lease; this bounded repair does not claim that view-once architecture.
- Five Swift files formatted together; integration build `build-Debug-20261002-211637-8286-29034.log`: PASS10s, zero warnings.
  First actual-view probe failed its immediate deinit assumption after window removal. `b845ae0` waits for bounded queued UIKit
  teardown while ACK remains suspended, with a weak condition; the view is gone before the reply. Exact transient retention cause
  is unproven. Production is unchanged. One-file build `build-Debug-20261002-211911-11904-22812.log`: PASS8s, zero warnings.
- Audit Simulator source `9844135` plus the committed probe fix, PID `12358`: actual UIKit/native-player/private-MP4/JPEG probe
  passes nil/stale backend pixels, unsupported forms, ACK admission, late callbacks, positive TTL/elapsed metadata, repeated hold,
  source collision, edit/delete/reuse/window/offscreen/background revocation, canceled download, deinit and ordinary play/pause.
  Injected requests/clock produce no real opens, user-media operations or account writes. Real touch/server TTL ordering remains unverified.
- Source `b845ae0`, PID `13038`: profile/media reveal, text-spoiler and navigation regressions pass with fresh file timestamps.
  Separate native inline-animation PID `15898` and gallery-owner PID `16179` pass; same owner/item/layer, finite FFmpeg ranges,
  cancellation and offscreen continuity retained. Active system PiP unsupported. Proofs and initial failure:
  `.build/ui-probe-evidence/astra-a21c-primary`. Worker build/ref notes remain in its `.build/video-note-hold-proof`.
