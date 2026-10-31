# A21d secret video-note scene-capture admission — 2026-10-02

- `49b914b` (worker `5d141f6`) requires an attached window and inherited UIKit `sceneCaptureState == .inactive` at hold,
  metadata, download, ACK and player/pixel admission. Active/unspecified capture and detachment deny the secret hold.
  A trait callback synchronously conceals pixels, stops the player and retires owned download/hold authority. Ending capture
  does not revive a hold or extend its monotonic deadline; a new hold is required. Ordinary notes remain unaffected.
- Reference: the current/pre secret viewer and `ChatImageGalleryItem.swift` capture-protected path cited above. UIKit 26.5
  `UITraitSceneCaptureState`/`registerForTraitChanges` supply scene recording/mirroring state. TDLib APIs are unchanged.
  This is a conservative display gate, not screenshot prevention or a guarantee that hardware cannot capture the first frame.
- `10cf90d` (worker `9ac9219`) verifies real container-to-view trait inheritance without overriding the leaf, then explicit
  active/inactive/unspecified boundaries. Existing fixtures inherit actual scene traits. Both changed Swift files formatted
  together; primary `build-Debug-20261002-225546-56715-10303.log`: PASS11s, zero warnings.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS26.5, source `10cf90d`, PID `58077`: full actual-UIKit/native-player/
  private-MP4 hold probe passes, including pending I/O, ACK, visible pixels, rehold and ordinary-note regressions.
  Output mtime `2026-10-02 22:56:55`; private proof `.build/ui-probe-evidence/astra-a21-capture-primary`.
  No real secret content opened or account write performed. Hardware recording/touch/server behavior remains unverified;
  photo/video/animation and immediate/view-once playback remain separate concealed gaps.
