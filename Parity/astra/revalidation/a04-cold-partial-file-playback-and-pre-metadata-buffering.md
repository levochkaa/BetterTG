# A04 cold partial-file playback and pre-metadata buffering — 2026-10-03

- Base `218e863`; reviewed `TDLibVODFFmpegSampleBufferPlayer`, range source/DEBUG transport and new
  `TDLibVODPartialCoverageProbe`. Existing small-file proofs remain valid within their limits. A new native AVAssetWriter
  fixture contains 24s of actual H.264 video (480×270/15fps), 13,324,774 bytes, not padding around a tiny clip. Generation and
  hashing run off main with one pixel buffer at a time. TDLib availability is injected into the real range source/FFmpeg/player.
- Confirmed P2: `updatePlaybackGate` returned before current decoder metadata existed. Initial lookahead can wait on missing
  seek bytes before that metadata arrives, so `.preparing` never became `.buffering`. PID47925 reproduces
  `preparing → failed`, no buffering, and the 12s no-video watchdog. The fixture deliberately withheld tail bytes until buffering;
  this is evidence of the missing state transition, not evidence that delayed downloads always fail in production.
- Repair is a guard split only: for a current prepared/open/error-free renderer, missing metadata schedules the existing
  generation-fenced 300ms transition when playback is requested, visible and has a decode task. No decode/range/seek-completion
  or renderer-readiness rule is relaxed. Pause/offscreen/seek/close cancellation is retained. Reference: current official
  `6ad963e5` and pre-Liquid `8e7e5fef`, `MediaPlayer/Sources/ChunkMediaPlayerV2.swift:599–613,708–722`: unavailable/new direct
  reader is buffering; display delay is 0.3s. TDLib remains pinned to `022d6020`; real transport contracts remain
  `downloadFile(offset/limit)`, `getFileDownloadedPrefixSize`, `updateFile` and `cancelDownloadFile`.
- Native PASS PID54595 at 04:40:26 +04, audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS26.5:
  display-ready playback reached 0.3468s with 5,852,379/13,324,774 cached bytes and the second half unavailable. Seek18s
  requested `10206788..<12303940`, stayed buffering without completing, respected 400ms pause and 400ms offscreen intervals,
  then made a new request on visibility return. Revealing the requested range plus a source update resumed display-ready playback
  at 18.237s with 8,970,365 cached bytes, still incomplete. Six nonempty finite in-file requests, no full-download call, drained
  transport/cancellation and temporary-file cleanup. Unique coverage is a union, not an overlapping-range sum.
- Preserve failed fixture evidence: PID42870 first reproduced the missing transition without detailed failure logging;
  PID47925 captured the watchdog/state sequence. After the guard fix, PID50903 passed buffering/resume but failed an incorrect
  DEBUG `limit <= 2MiB` assertion: existing fetchPlan intentionally extends overlapping ranges. The corrected assertion checks
  nonzero finite in-file bounds, with incomplete coverage checked independently. No production fetch policy was changed.
- Existing FFmpeg controller/main-track regression PASS PID55178: pause/rate/offscreen/last-seek, persistent 10-window/one-open
  session, EOF, offline/retry, explicit short-video end, under/overestimated duration and beyond-EOF clamp; zero renderer errors.
  Real root list was visible after teardown (`after-controller.png`). No sends, account switch, reset, Simulator focus activation
  or shutdown. Saved results: `.build/ui-probe-evidence/astra-a04-partial-coverage/`.
- One three-file SwiftFormat invocation, wrapper build `build-Debug-20261003-043953-54182-14840.log` PASS6s; complete log has
  zero warnings/errors. Independent read-only review accepted production guard, actual prefix-gated file reads, teardown and
  proof limits. This proves injected availability with real native decoding/display readiness; not live TDLib/server delivery,
  A/V sync for the large video-only fixture, physical hardware or active PiP. Reveal + update jointly precede recovery; this
  does not isolate updateFile as the sole wakeup rather than timeout/refetch. Lookahead estimate authority remains open.
