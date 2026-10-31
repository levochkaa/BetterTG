# A20a route-owned media concealment — 2026-10-02

- `929eb94` (worker `113e443`) introduces route-owned account/client/chat authority and per-member media-revision permits.
  Keys include content kind, source file IDs, edit revision and spoiler/secret flags; download progress does not erase a reveal.
  Timeline first tap reveals only the selected spoiler; second tap opens gallery. Gallery grants only its central item and retains
  the issuing session through PiP restoration. Secret photo/video/animation remain concealed and cannot enter ordinary playback.
- Admission happens before image/player/thumbnail creation or prefetch. Concealed UIKit covers contain no raw media beneath them.
  Single/album AX is sanitized; captions retain independent A10 semantics. Photo/video loads use the captured client.
  Transition capture and later snapshot access check the exact revision and rendered generation.
- Accepted Chat model changes synchronously revoke old permits before queued UI work, cancel pending prefetch and invalidate
  owners. Gallery receives the accepted replacement payload; same-ID updates reconfigure visible cells and require a new reveal.
  Reconciliation is guarded against recursive notifications. Covered timeline cells refresh revealed members on gallery return.
- Reference: pinned current/pre `ChatMessageInteractiveMediaNode.swift` spoiler/secret admission 925/946 / 923/944 and
  concealment 3094 / 2948–2988; pinned TDLib `MessagePhoto/MessageVideo/MessageAnimation.hasSpoiler/isSecret` contracts.
  This bounded implementation uses an opaque cover; upstream blur/particle polish and full visual parity are not claimed.
- Eight Swift files formatted together; integration build `build-Debug-20261002-203725-34161-16930.log`: PASS18s, zero warnings.
  Audit Simulator source `929eb94`, PID `39784`: media-reveal, text-spoiler and viewport probes pass. Native AVAssetWriter fixture,
  actual gallery cell/controller/owner and isolated range backend prove selected-only admission, no pre-reveal downloads,
  revision cancellation, stale snapshots and issuing-session retention. PID `40544`: native inline-animation and gallery-transition
  regressions pass. PID `40966`: gallery-owner native/FFmpeg continuity, finite ranges and teardown pass. PID `42082`:
  isolated PiP context/restoration regression passes; active system PiP remains unsupported. Readbacks:
  `.build/ui-probe-evidence/astra-a20a-primary`.
- Same PID `42082` opens actual Saved Messages with its ordinary text history and composer intact; no hidden media was selected.
  Private `saved-chat.png` records this limited UI smoke. Documentation checkpoint build
  `build-Debug-20261002-204324-42880-29193.log`: PASS5s, zero warnings.
- Policy-level first/second tap proof is not a real timeline gesture. Actual TDLib transport, spoiler UI gestures, real PiP,
  profile grid, full accessibility and animation appearance remain unverified. Profile concealment is the next bounded repair.
  Same-epoch stale RPC ordering is not solved by revision permits. No real hidden/secret message was opened or consumed.
