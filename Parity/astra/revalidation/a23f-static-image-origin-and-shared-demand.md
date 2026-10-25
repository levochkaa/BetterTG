# A23f static-image origin and shared demand — 2026-10-02

- `d2fd3f9` (worker `73bcb04`) requires an explicit originating client or frozen `TDImageOrigin` at every static-image entry.
  Admission precedes minithumbnail/cache/local decode/download. Placeholder/cache-only loads also revoke on source changes.
  Avatars and GIF tiles retain their source instead of rebinding an old File to a new client; folder, sender, reply, pin,
  forwarding, composer and profile consumers pass their existing captured client. Empty photos retire the prior request.
- Static images and `.none` prefetch use the existing account/client/file demand pool. Cancel releases one lease; last-owner
  cancellation and reacquisition remain serialized. Voice/video-note full-file prefetch stays fire-and-forget/unpooled, without
  file-global cancel; it is outside these shared-cancel guarantees. VOD offset/limit transport is unchanged. Decode remains off-main
  and request/source fenced. Detached native decode is not interrupted mid-operation; cache resolution policy is unchanged.
- References: pinned current/pre `ChatMessageInteractiveMediaNode.swift` 1370 / 1364 binds image work to its account;
  `FetchManagerImpl.swift` 797/823 registers/removes consumers. Pinned TDLib `downloadFile/cancelDownloadFile/updateFile`
  (`td_api.tl` 13778–13790): file identity is client-local, and cancellation is file-wide. No upstream infrastructure copied.
- All 22 Swift files formatted together; integration `build-Debug-20261002-214759-61736-17727.log`: PASS18s, zero warnings.
  Main and independent delta reviews found no introduced production blocker. Audit Simulator source `d2fd3f9`, PID `63466`:
  static-image/shared-demand/scoped-delivery probes pass with actual UIImageViews and private PNGs. Nil/stale/cache/source
  collision, multiple views plus prefetch, last release/reacquire, late RPC/decode, reuse and deinit are covered without server writes.
- PID `69030`: media-reveal and text-spoiler pass, but profile-grid fixture fails `ordinary media regressed`. Its thumbnail
  injector retained the initial fixture's origin after creating a replacement-client fixture. `c519e98` changes only that
  DEBUG fixture wiring, preserving the earlier stale-origin assertions. One-file format/build
  `build-Debug-20261002-215620-70529-12978.log`: PASS9s, zero warnings. PID `70966`: profile-grid, static-image, shared-demand
  and scoped-delivery all pass. Initial failure is retained under `initial-d2fd3f9`, not erased or counted as a pass.
- Actual Saved Messages → Profile at `d2fd3f9`, PID `69030`: avatar and populated shared-media grid load; full header title,
  402pt header/362pt labels/96pt avatar remain correct. No media/editor/message mutation selected. Separate PID `53678` at
  `c519e98`: timed video-note hold/native-player regression passes. Native inline-animation PID `9931` and gallery-owner PID `24400`
  pass separately; active system PiP remains unsupported. Private evidence: `.build/ui-probe-evidence/astra-a23-static-primary`.
  Live multi-account switching, real canceled TDLib downloads, unpooled prefetch and every thumbnail consumer remain unverified.
- Further bounded source audit at `d2fd3f9`: pending nonzero position → suspended metadata → order0 removal → late append
  can resurrect a row. Existing `chatRefreshIDs` guards overlapping refreshes, not this insertion. A23g will guard semantic-list
  membership through hydration. Pinned TDLib `td_api.tl`10403–10406 requires order0 removal and allows positions through last-message/draft;
  11473–11476 says `getChats` is informational, not an atomic list-state source. Bulk rebuild/settings races remain A34/A35.
