# Fullscreen gallery caption and total-count slice

- **P1 flow:** current/pre-Liquid gallery caption footer, spoiler/entity interaction and absolute position index, adapted to UIKit TextKit
  and the existing TDLib message stream.
- Implemented: formatted photo/video/animation captions; validated UTF-16 entities; scaled bold/italic/code runs refreshed on content-size
  changes; 44…220pt scroll container (96pt compact cap) rather than truncation; scroll position per selected message; caption-scroll hold
  that keeps unified chrome/video controls visible until return to top. Dynamic caption height raises the 136pt video controls above
  `50 + captionHeight`. Spoilers are opaque before reveal, redacted from AX, reveal by hit-test or AX action, then publish non-hidden
  URL/email/phone/mention AX actions. Concealed `textUrl` destinations compare normalized scheme/host/default-port/path/query/fragment
  and require an explicit URL confirmation when they differ. Profile listens to active-account content/edit updates, generation-serializes
  `getMessage`, preserves topic scope, and reconfigures same-ID captions. Profile search passes TDLib `totalCount`; loaded-page appends and
  deletes update messages before re-clamping that total.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-121611-18495-8647.log`; final source/delta review CLEAN. PID `18804`
  exposes a real `Caption, …` label at 378×28 and `1 of 88`; captioned video proof shows scrub/transport entirely above
  its caption, with footer below. Screenshots: `.build/ui-probe-evidence/profile-gallery-caption-entities-final.png` and
  `.build/ui-probe-evidence/profile-gallery-caption-video-controls.png`. No entity URL, Share or server mutation was activated.
- Runtime blockers: reachable sampled captions contain no spoiler or concealed `textUrl`, and no long caption was safely selected, so
  reveal/confirmation/scroll-hold are source-reviewed and build-proved but not deliberately exercised on account data.
