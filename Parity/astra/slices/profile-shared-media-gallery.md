# Profile shared-media gallery slice

- **P1 flow:** peer-info media pane → production gallery from current/pre-Liquid `PeerInfoPaneContainerNode.swift` and
  `PeerInfoScreenOpenMessage.swift`, retaining the `ChatLocation` history source and a fresh visible transition provider.
- Implemented: Media-only gallery routing while Files/Links/Audio keep open-in-chat; exact thumbnail snapshot without the video badge;
  represented-ID + visible-cell + account validation; profile retained beneath the modal; newest→oldest selected-ID-stable append-only
  pages; one in-flight mutation queue; boundary retry; no reload jump; active-account fencing before cell/VOD/PiP creation; release and
  fade on account switch; active-client permanent photo/video delete reconciliation; selected-delete forced fade. The footer is one
  full-width `systemChromeMaterialDark` surface through the bottom safe area with plain 52×50 Close/Share and a nontruncating index.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-111604-5080-25531.log`; final source/delta review CLEAN. PID `5495`
  opened the first profile tile as `1 of 30`, paged to the exact full `2 of 30`, then Close returned to Profile with the original
  131×131 source tile still present. AX proves `gallery-close`, `gallery-counter`, `gallery-share` on the full-width footer; screenshot
  `.build/ui-probe-evidence/profile-gallery-authoritative-classic-footer.png`. No Share or server mutation was performed.
- Deferred: avatar/photo-video header history, interactive pan-dismiss, captions, save/forward/delete/open-in-chat,
  rotation/current-item runtime proof, and deliberate near-page-boundary/error/account-switch/delete smoke.
