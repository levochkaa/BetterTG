# A30f2 activation and A38 admission review — 2026-10-02–03

- `0ead5fc` (worker `35adb4d`) restores only the topmost quiescent profile with unchanged account/actor and the exact
  preceding restored Chat. Captured-client metadata reads, source/Ready/owner gates and terminal cleanup fence replacement;
  callbacks bind to the fresh Chat. Existing editor retention remains separate. Five-file format;
  `build-Debug-20261002-235658-67695-30825.log`: PASS11s, zero warnings.
- Native probe at `0ead5fc`, PID `68772`, passes actual seed/UICollectionView/history helpers and production coordinator
  with value-only navigation entries. Suspended metadata, repeated rollover, child/detached-owner and predispatch rejection
  pass; actual PeerProfile/ChatVM/TDLib are not injected by this fixture. Existing editor and folder probes also pass.
- Actual Saved → Profile → Files → Home → app icon retains PID `68772`, Files selection, accepted visible rows and header
  geometry. Lifecycle log: ownership released `00:05:16`, restored `00:05:41`, profile replacement accepted `00:05:42`.
  Search then opens the fresh Saved Chat's focused search field. No file/gallery was opened and no message/profile/folder
  was sent or saved. Scrolled anchor, Open in Chat, repeated actual rollover and live account switch remain unverified.
  Private proof `.build/ui-probe-evidence/astra-a30f2-activation-primary`. idb timeout cleanup prints an asyncio warning;
  this is tool cleanup, not an app crash.
- Independent delta review found A38: old seed values receive new media authority without message revalidation. The route
  smoke above proves navigation/state only. Repair boundary: reuse a profile-owned bounded revision/read scheduler, close
  all unverified pixel/AX/action paths, preserve raw pagination and viewport; permanent deletion and newer partial updates
  must defeat delayed getMessage/search pages. Errors remain retryable, not fabricated deletion. No ChatVM/Root rewrite.
