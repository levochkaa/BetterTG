# A20b profile-grid media concealment — 2026-10-02

- `a126e04` (worker `3f1f359`) gives shared-media cells the profile's frozen playback context and issuing reveal session.
  Thumbnail/minithumbnail loading, visible badges, accessibility and transitions require the current member revision. Concealed
  cells contain an opaque cover without raw media below it. Source/revision/reuse invalidation cancels loading and clears pixels.
  Accepted profile snapshots reconcile permits before diffable delivery and refresh retained same-ID cells and the active gallery.
- Selecting a profile-grid item opens the existing gallery and grants only its selected member. Return refreshes visible grants;
  timeline's separate first-tap/second-tap contract is unchanged. Secret media remains denied; file/link/audio rows and avatar
  handling are unchanged. Revision permits do not solve same-epoch stale RPC ordering or profile client replacement.
- References: pinned current/pre `TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoVisualMediaPaneNode.swift`
  895–933,1322–1337,1898–1907 / 875–913,1273–1288,1816–1825; pinned TDLib media `hasSpoiler/isSecret` and file contracts.
- Primary review corrected a probe assumption about rasterized transition views. `0278eca` (worker `e5fffa7`) checks actual
  UIImageView snapshot pixels: the private red fixture is absent while covered and present after reveal. No production policy change.
  Three Swift files formatted together; `build-Debug-20261002-210753-97781-13866.log`: PASS10s, zero warnings.
- Audit Simulator source `0278eca`, PID `473`: profile-media-reveal, media-reveal, text-spoiler and client-restoration probes pass.
  Actual cell/gallery plus private fixture cover zero pre-reveal thumbnail calls, revision/source revocation, reuse, stale snapshots
  and sanitized AX. This is not a full profile-controller, real TDLib transport or actual spoiler-touch test.
- Same launch: Saved Messages → own Profile displays the avatar, Media/Files/Links/Audio controls and populated media grid.
  No media item, hidden content, editor or server action was opened. Private screenshots/proofs:
  `.build/ui-probe-evidence/astra-a20b-primary`. Circular Back remains an A32 gap; the visibly truncated title is recorded as A33.
  Hardware/VoiceOver, populated-grid updates, actual spoiler gestures and full visual parity remain unverified.
