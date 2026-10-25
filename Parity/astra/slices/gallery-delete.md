# Gallery Delete slice

- **P1/P0 flow:** Telegram current/pre-Liquid gallery item/group deletion and revoke-mode confirmation, adapted to one captured TDLibKit
  client and the same authoritative album resolver as Forward.
- Implemented: Delete is absent for secret/self-destruct media and serialized with Open/Save/Share/Forward. Single media proceeds to
  authority checks; a proven album first offers destructive `This Item` / `All N Items`, while unresolved history safely degrades to the
  selected item. Every chosen ID receives fresh exact-chat/topic `getMessage` plus `getMessageProperties`; permissions intersect across
  the complete set. Confirmation exposes `Delete for Me` only when every ID supports local deletion and `Delete for Everyone` only when
  every ID supports revoke. Immediately before commit, the same messages/properties/mode are fetched and checked again. One captured
  `deleteMessages` call is issued; no optimistic removal, multi-call partial state or automatic retry exists. An unconfirmed post-enqueue
  failure tells the user to inspect whether media remains.
- The controller now observes permanent deletes for photo/animation/sticker as well as video. Per-chat ID unions coalesce rapid events
  across diffable batches and interactive dismissal, merge owner callbacks, filter the newest pending canonical message list once and
  adjust the authoritative total once. Video owners are marked terminal and removed before release, revoking PiP/restore and preventing
  deleted playback from returning inline. Selected deletion uses a pre-enqueue snapshot and exactly-once forced fade; no dust/particles.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-144807-65887-7317.log`; final Telegram/TDLib lifecycle review CLEAN.
  PID `63543` exposed destructive `Delete` above Save/Forward/Open in the real gallery menu; it was not activated. Final unified build PID
  `66267` launched with Simulator still booted. Evidence: `.build/ui-probe-evidence/gallery-delete-action-visible.png`.
- Runtime blocker: destructive confirmation and `deleteMessages` were deliberately not exercised without separate approval; item/all,
  for-me/everyone, rapid-update union and video/PiP terminal branches are source-reviewed/build-proved.
