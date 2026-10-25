# Live profile metadata slice

- **P1 flow:** Telegram current/pre-Liquid signal-driven peer info data, adapted to BetterTG's active-client typed update bus and UIKit
  state rather than one-shot controller snapshots.
- Implemented: exact account/client and peer-ID guards for chat title/photo, user/status, basic group, supergroup and all three full-info
  updates. User/group payloads replace `CustomChat.type` immediately; title/status/usernames/phone/member noun/count update before any
  network round trip. Full-info payloads directly update bio/description/details/full `ChatPhoto`. Title/photo refetches use one monotonic
  `metadataGeneration`; full-info requests and pushed payloads share `fullInfoGeneration`; cancelled/older responses cannot overwrite a
  newer revision. First full-info hydration does not cancel a legitimate simultaneous avatar open, while later `ChatPhoto.id` changes
  increment avatar identity, cancel initial/history tasks, clear raw offset/dedupe/total, close stale avatar gallery and remove old
  animation authority. One run-loop-coalesced render updates title/status color/bio/details/avatar/placeholder/AX traits+hint/tap
  availability and Dynamic Type header height together.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-130032-28652-16080.log`; final source/delta review CLEAN. PID `29034`
  exposes the stable 96×96 `<group> profile photo`, title, `4 members`, actions, tabs and media after live subscriptions attach.
- Runtime blocker: no deliberate server title/photo/status/full-info mutation was performed on the safe account; update transitions are
  source-reviewed and build-proved, while the runtime smoke is a no-regression readback.
