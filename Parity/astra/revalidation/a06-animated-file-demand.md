# A06 animated-file demand — 2026-10-02

- `cbbfa64` replaces per-view transport cancellation with `AnimatedFileDemand`, keyed by originating account UUID, client ID and
  file ID. TGS/WebP/WebM views and animated prefetch acquire the same whole-file demand. Releasing one view or cancelled prefetch
  cannot cancel another registered consumer. The last release cancels only the pending download through its captured client.
  A replacement starts after the previous cancellation reply; a not-yet-cancelled start can instead be shared. Completed files,
  released owners and failed prefetch waiters leave no retained pool entries after their last lease. No cache/storage schema change.
- Scoped `updateFile` revisions outrank delayed initial-state RPC replies. Review caught queued terminal updates being dropped
  while cancellation was scheduled but not yet issued. The final code distinguishes scheduled/in-flight cancellation and replays
  both completed and inactive-failure state when cancellation is abandoned. Those exact races are now explicit regressions.
- References: pinned current/pre `FetchManagerImpl/Sources/FetchManagerImpl.swift` 779–823 (episode-scoped priority/reference
  acquisition and release), adapted without Telegram infrastructure. TDLibKit `downloadFile(offset:0,limit:0,synchronous:false)`
  plus accepted `updateFile` and `cancelDownloadFile(onlyIfPending:true)`. Shared animated demand uses priority 2; static `.none`
  prefetch remains at priority 1. VOD range ownership is deliberately separate: different offset/limit would supersede a TD request.
- Five Swift files formatted together. Final build `.build/logs/xcodebuild/build-Debug-20261002-185806-60504-4167.log` passes in
  6s, zero warnings. Initial DEBUG-only actor-isolation compile failure was corrected before this build. Audit Simulator
  `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro / iOS 26.5, installed source `cbbfa64`, PID `60930`:
  `-media-probe-animation-demand`, `-media-probe-animation-authority` and `-ui-probe-chat-restoration-state` all pass. Results:
  `.build/ui-probe-evidence/astra-a06-primary`. Parent and independent delta reviews completed, including the terminal-race repair.
- Demand tests run actual production pool/request code with isolated suspended transport and notifications: duplicate visible
  owners, deinit, cancelled prefetch, pending start reuse, delayed cancel/reacquire, queued completion/failure, stale initial reply,
  client replacement, pre-start cancellation, completed cache and explicit retry. No server calls or user stores. Actual three-view
  decode callbacks/TDLib scheduler, nonanimated downloads and cross-arbitration with VOD ranges are not established by these probes.
