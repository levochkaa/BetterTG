# BetterTG / Telegram iOS Parity

This file is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation. Telegram references use
`telegram-upstream/master` unless a commit is pinned. The classic pre-Liquid baseline is
`8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, the parent of Telegram's first first-parent `Glass` commit.

Implementation status and verification are separate. **done** means the recorded bounded scope has its stated proof;
**implemented breadth** means the main code paths exist, with the listed verification limits; **partial** has known gaps;
**next** identifies the next bounded slice; **queued** has not started. None implies exhaustive Telegram parity.
Gifts, Stars, collectibles, boosts, Premium, ads, livestreaming, and Telegram infrastructure
(Texture, SignalKit, Postbox, Display, ComponentFlow) are intentionally out of scope.

## Revalidation before new features — 2026-10-02

The user requested a fresh `gpt-6-astra` review of the accumulated implementation previously developed with `5.6-sol`.
The initial documentation handoff was `6b417da`; the goal subsequently started on 2026-10-02 from that clean HEAD, whose last
production commit was `7b0699d789329535786cc6170c98287c45d52ebb`. There is no `GOAL.md` in this checkout. The reusable revised
objective is [PARITY_PROMPT.md](PARITY_PROMPT.md); the previously started goal points to the user-supplied attachment.
Editing these documents does not start or resume a goal. The current request is a bounded handoff: close already-started safe
slices, retain the audit backlog and stop until an explicit resume. This does not mean Telegram parity is complete.
Re-read HEAD and dirty state on resume.

All existing implementation and CLEAN/build/probe/smoke claims in the old ledger remain historical evidence. Their new audit status
starts as **pending**, including flows called done or implemented; the audit results below record subsequent coverage and findings.
Preserve the original evidence and its limits; a past clean build,
zero-marker scan, catalog switch or permission-denial smoke does not prove complete behavior on the current revision.
Historical slice-level Deferred/Remaining/next notes describe those slices at the time; reconcile them with later slices and
current code before scheduling duplicate work. This section and the current checkpoint take precedence for resume ordering.

### Audit workflow

1. Read `AGENTS.md`, `CLAUDE.md`, `project.yml`, this ledger, current code, working/index diffs and committed implementation history.
   Establish the relevant implementation base from Git history. A clean working diff is not an audit of accumulated changes.
   Inventory every flow, production entry point and shared dependency; preserve unrelated user changes and existing behavior.
2. Pin the inspected official `telegram-upstream/master` SHA and the relevant pre-Liquid reference for each flow. Use Swiftgram
   only for toggles. Verify against the pinned TDLibKit API/models, not remembered signatures or copied Telegram infrastructure.
3. Review the areas below in bounded slices, prioritizing P0 correctness and cross-flow ownership. Follow actual production
   callers, data and lifetime transitions; flag placeholders, dead paths, missing integration and overclaimed proof. Do not merely
   review the latest commit, rescan names or reread previous summaries. Fix confirmed P0/P1 findings as their area is reviewed.
4. Rewrite only for a demonstrated defect, behavioral gap, lifecycle/ownership problem, measured performance problem or avoidable
   complexity with a concrete maintenance cost. Record the evidence, replacement scope, preserved behavior/data contracts and
   regression checks before editing. A model change alone is not a rewrite reason. Keep changes bounded and avoid wholesale
   restarts or speculative abstraction.
5. For each area, record review date, reviewed SHA/files, Telegram SHA/path, TDLib version/API, findings by P0/P1/P2, fix commits,
   proof commands/device and blockers.
   Use audit states `pending`, `reviewed`, `needs-fix`, `fixed`, `runtime-blocked`; retain unresolved findings when runtime is blocked.
   Separate source review, warning-free build, deterministic probe, Simulator smoke and physical-device/server proof. Missing
   evidence is unverified, not passed; mark unavailable fixtures/permissions/hardware explicitly and continue independent work.
6. Before new feature breadth, cover every area once and close actionable P0/P1 findings; log externally blocked checks with a
   next action. Then select the highest-priority useful gap, not automatically the previous profile-management next step.
   On later resumes, continue from the recorded audit cursor and recheck changed dependencies; do not restart the entire audit.
   Proof belongs to a SHA, scenario and environment. Changed contracts, ownership or shared dependencies require a narrow
   recheck of affected flows; historical CLEAN does not automatically transfer, including to new Astra-authored repairs.
7. An explicit stop request overrides continuous gap selection. Finish only the current safe slice, stop delegated work,
   record unresolved scope and pause. A budget boundary or document edit is neither completion nor authorization to resume.

| Priority | Area to revalidate | Required checks | New audit state |
| --- | --- | --- | --- |
| P0 | MediaCore and animated media | No VLC dependency/consumer; production TGS/WebP/WebM-alpha and custom/animated emoji routes; decode ownership, alpha/timing/sync, bounded caches, offscreen pause, prefetch/cancel/fallback | needs-fix — first source pass; A07 fixed/probed, A05/A06/A08/A09 remain; authenticated animation smoke pending |
| P0 | Voice and video notes | Ogg Opus/waveform and H.264/AAC output; hold/cancel/lock, pause/resume, preview/seek/trim, cameras/limits; durable draft/send/retry ownership, interruptions, relaunch and terminal cleanup | needs-fix — voice source pass A11–A14; video audit pending |
| P0 | VOD, FFmpeg and PiP | Playback before full download, finite offset/limit reads, prefix/EOF checks, seek/refetch, lookahead, cancellation leases, buffering/offline/retry; same owner/playhead across inline/fullscreen/PiP, A/V sync and bounded memory | needs-fix — range/decoder/renderer source pass; A01–A04 below; owner/PiP audit incomplete |
| P0 | Message content and actions | Current generated MessageContent cases mapped to real rendering/actions and safe fallback; entities/web/captions/spoilers, albums, polls/quiz/dice/service; reply/quote/forward/edit/delete/select/reactions/pins/topics/unread/delivery | needs-fix — text spoiler A10 confirmed in source; full area audit pending |
| P0 | Composer and timeline | Complete island states and production sends; temporary/final IDs and snapshot transitions; stable IDs, raw pagination, messageId+pixelOffset under prepend/edit/resize/keyboard; cancel/retry, prefetch, off-main work | pending |
| P0/P1 | Cross-flow account and authority boundaries | Captured client/account/chat/topic; stale callbacks, Combine/task teardown, updates, storage/cache keys, permission revalidation; pending sends/deletes/account switches; shared player/file/audio ownership | needs-fix — animation A05/A06 and voice A12–A14; remaining cross-flow audit pending |
| P1 | Profiles and galleries | Peer/self roles, avatar/history, member/admin/tag rights, shared-media pagination; selected item, transitions, zoom/paging/dismiss/control gestures, rotation, captions, export/forward/delete/open-in-chat | pending |
| P1/P2 | Accounts, chat lists/folders and classic shell | Inventory existing add/auth/switch/remove/logout paths and missing isolation; archive/search/edit/reorder/include/exclude/pin/mute/read/delete/clear/drafts; safe-area full-width blur and prohibited production UI markers | pending |

Read-only audit subagents return findings and need no commit or duplicate build. At most two subagents may run concurrently.
Implementation subagents use isolated worktrees, format changed Swift in one invocation, build without warnings and commit;
the primary integrates verified commits and validates the combined result. Do not spawn when the remaining budget cannot cover
integration and verification. Each implementation slice must end with proof, a focused attributed commit and an updated checkpoint.

### Astra audit baseline and coverage

- Date/source: 2026-10-02, clean `6b417da362960e152f07ba86000b7777b636b0f5`. Pre-UIKit base is
  `67ecc4ff2287483652019b40f383d50015a35a77` (parent of `a543a0d`); VLC replacement began at `6216eee`, parent
  `0599bfdc8ff862a548b686b0f04df8b2f8ec28e5`. Audit current reachable code and the accumulated history, including integration
  merge `5d990c1`; other branches and unrelated push/build work are not authorization to merge or rewrite them.
- Official references: `telegram-upstream/master` = `6ad963e5b62d354da79040f388ae2b9132fb17b8`; classic baseline remains
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`. TDLibKit is pinned to `1.5.2-tdlib-1.8.66-022d6020`, TDLib `022d6020`;
  Lottie 4.6.1, libwebp 1.6.0 and checksum-pinned FFmpeg 9.0 are unchanged.
- Current marker scan over `project.yml`, `BetterTG`, `BetterTGNotificationService` and `Packages` found no VLC API/dependency,
  SwiftUI/hosting/representable or Liquid Glass production marker. This is a dependency/source check, not visual/runtime parity.

| Area | Production entry points and shared dependencies located | Coverage at this checkpoint |
| --- | --- | --- |
| Animated media | `MessageContentView`, `MessageTextView`, reactions, composer picker and gallery → `AnimatedFileView`, TGS/WebP/FFmpeg views, `CustomEmojiStickerRepository` | Source pass through these consumers; A07 worker lifecycle/reuse probe passed, other runtime coverage and fixes outstanding |
| Voice/video notes | `ChatBottomArea`, `VideoNoteRecorderViewController`, `ChatVM` → capture/writer/codec, recording/send stores and coordinators, message playback | Voice source pass at `37c8b44`: recording/trim/PCM/codec, preview, send/retry/relaunch/outcomes and destination ownership; A11–A14. Video remains inventory only |
| VOD | `ChatView`/`ChatViewAlbum` → `GalleryVideoPlaybackOwner`, `LocalMediaPlayer` or FFmpeg sample player → range coordinator/resource loader/decoder/renderer/C AVIO | Source pass over range/loader and C/Swift decoder/render session; complete owner/PiP review pending |
| Content/actions | `MessageContentPresentation`, `MessageMetadataPresentation`, structured/text/reaction views → `ChatVM`, `MessageForwardingService`, topic/forward controllers | Inventory plus confirmed source-only spoiler finding A10; complete rendering/action audit pending |
| Composer/timeline | `ChatBottomArea`, `ChatView`, `ChatVM`, `ChatDraftKey`, `MessageSendTransition`, date/topic header models | Inventory only; not re-reviewed |
| Profiles/gallery | Peer profile/control/avatar controllers → `ChatViewAlbum` gallery and owner/export/actions | Inventory only; not re-reviewed |
| Accounts | `TDLib`, `TelegramAccountRegistry`, root/settings controllers → client activation/retirement, storage, update subjects | Add/switch/remove code already exists; previous queued label was stale. Isolation audit remains incomplete |
| Lists/shell | `MainView`, `RootVM`, `FolderView`, `ChatFolderManagementViewController`, navigation/context-menu views | Inventory only; not re-reviewed |

### Astra findings and repair queue

Locations A01–A10 refer to the reviewed `6b417da` implementation unless a fix is recorded; voice A11–A14 were reviewed at
`37c8b44`. Source findings are not runtime proof. A repaired finding does not mark its entire area fixed.

| ID | Priority | Evidence / trigger | State and bounded repair |
| --- | --- | --- | --- |
| A01 | P1 | `TDLibVODRangeSource.waitForSignal/timeoutWaiter`: canceled sleep still invokes timeout; a repeated wait reuses read ID and seek generation, allowing an old callback to consume its replacement | fixed in `37c8b44`: per-registration token, cancellation return; obsolete/current-deadline probe passed |
| A02 | P1 | `ensureAvailable` can receive `updateFile` while awaiting an older zero-prefix RPC result, then register after the only wakeup; bytes wait for timeout despite being cached | fixed in `37c8b44`: compare update sequence before registering at all three wait sites; suspended-prefix production-read regression passed |
| A03 | P1 | `FFmpegSampleBufferRenderer.pause` publishes on every call; player snapshot delivery calls `updatePlaybackGate`, which pauses again in paused/buffering/EOF states | fixed in `3005369`: deduplicate complete identical snapshots while preserving every pause transport command; settled feedback, seek/rate/EOF/offline/retry probes passed |
| A04 | P1 | Decoder/controller expose maximum A/V duration, but readiness always requires video; a 5s-video/60s-audio file accepts a 20s seek with no possible video frame and reaches watchdog failure | needs-fix: consistent video-main-track end policy matching upstream `video ?? audio`, plus unequal-track controller proof |
| A05 | P1 | TGS/WebP/FFmpeg animation views use global `nc.updateFile` plus numeric file ID and deferred dynamic `td`; account switch precedes root teardown. Custom-emoji fetch also resolves a dynamic client | needs-fix: capture account/client/file generation and propagate it through consumers; reject foreign updates/completions |
| A06 | P1 | Animation view teardown/prefetch calls global file cancellation without shared demand ownership; one reused copy can cancel another visible copy's pending download | needs-fix: account/client-scoped file demand leases covering visible consumers and prefetch |
| A07 | P1 | `FFmpegAnimatedVideoView.show` constructs its decoder on MainActor; initializer opens/probes FFmpeg input and codecs synchronously, even on asset-cache hits | fixed in `3917128`: native-free init, worker-isolated prepare/read/reset/deinit and setup/reuse fences; actual native-operation thread/lifecycle probe passed before and after integration |
| A08 | P1 | FFmpeg animation indexes use capped 30 FPS and at most 600 estimated frames while decoder returns every source frame; 60 FPS and long animations never reach real EOF, variable-duration GIF timing is lost | needs-fix: PTS/duration scheduling and decoder EOF, separately bounded cache |
| A09 | P1 | Apple-container `messageAnimation` routes to static `FileMediaPreviewView`; only fullscreen owns playback | needs-fix: account-scoped inline AVFoundation animation loop with visibility/reuse/cancel contracts |
| A10 | P1 | `Utils/Text.swift` spoiler formatting only adds background color; `MessageTextView.configure` retains visible text/custom emoji and exposes unredacted text through accessibility | needs-fix — primary source check confirmed; add hidden/revealed text and overlay/AX contracts, distinct from the already implemented gallery-caption spoiler path |
| A11 | P1 | `ChatView.viewDidDisappear` → `ChatBottomArea.cancelActiveRecordingGesture` → `ChatVM.cancelVoiceRecording` deletes the saved preview/WAV on Back because preview keeps `recordingVoiceNote == true`; permission loss uses the same teardown | needs-fix — separate navigation/gesture teardown from explicit discard; verify preview/trim/reply survive Back/reopen/relaunch and permission loss |
| A12 | P1 | Voice coordinator derives outcome destination from the delivered message topic, but an all-messages draft owns `destination.topic == nil` with separate `sendTopic`; store lookups require exact route equality before and after enqueue registration | needs-fix — match captured account/chat/temporary ID plus frozen delivery topic, preserve original draft route; probe early/late success/failure for All Messages and explicit topics |
| A13 | P1 | Voice coordinator reads current active account after `NotificationCenter.publisher` defers delivery to main; an account switch between posting and delivery can attribute A's outcome/delete to B with colliding IDs | needs-fix — capture event provenance at the TDLib boundary, carry it across delivery; probe post-A → switch-B → deliver-A without mutating B |
| A14 | P1 | `ChatVM.startVoiceFinalization` persists an adopted draft before encoding, but sets enqueue ownership only later; a reopened ChatVM restores it as retryable while the previous owner still encodes/sends; store has no finalization/file reservation | needs-fix — atomic per-draft runtime lease before adoption/encoding, canonical state validation and recoverable durable state; probe concurrent reopen/retry/discard and process-death recovery |

Reference contracts: pre-Liquid `MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift` registers range data and cancel
observers before waiting (lines 20–38), uses bounded read/lookahead windows (lines 189–212) and selects video as the main track
(lines 545/578). `ChunkMediaPlayerV2.swift` changes synchronizer rate only when effective rate differs (lines 699–702).
Animation references: pre-Liquid `AnimatedStickerNode.swift` source creation outside main (lines 477–507), `SoftwareVideoSource.swift`
PTS/duration (213–227), `EmojiTextAttachmentView.swift` account/visibility ownership; current `VideoStickerFrameSource.swift` derives
frame count at EOF (351/409–420). No Telegram infrastructure is copied.
Voice references: current `ChatControllerMediaRecording.swift` preserves preview resource/waveform/trim/resume state
(305–329, 640–663); pre-Liquid `ChatInterfaceState.swift` persists peer/thread-scoped media drafts (726–730, 899–918),
and `ManagedAudioRecorder.swift` materializes pause/resume/trim before append (486–538). Voice findings are source-only;
the existing codec probe's all-messages outcome uses the original route and therefore does not exercise A12's coordinator mismatch.

Positive source checks: bounded cancellable TGS inflate, copied premultiplied WebP/FFmpeg frames, bounded frame caches, first-frame
fallback; checked C AVIO arithmetic/packet ownership, serialized close/cancel and retained Swift callback contexts. These checks do not
close runtime gaps. P2 follow-ups include TGS parsed-cache byte bounds, custom-emoji metadata eviction, repainting and glyph advance.

### Range-waiter repair proof — 2026-10-02

- Scope: A01/A02 only. Preserve range planning, source/client ownership, finite fetch limits and cancellation generations. A fresh
  UUID identifies each waiter registration; sleep cancellation exits, and a delayed old callback cannot expire a replacement.
  Update-sequence checks cover size discovery, full-file fallback and range-prefix waits without losing an already-delivered update.
- One SwiftFormat invocation covered `TDLibVODRangeSource.swift`; `./build.sh build` passed without warnings in
  `.build/logs/xcodebuild/build-Debug-20261002-141955-60817-17803.log`. Independent diff review found no blocker.
- `./build.sh run --skip-build -- -media-probe-vod-ranges`, iPhone 17 Pro / iOS 26.5,
  `8108A92F-7E93-49C8-87F4-FA53A5A40A99`, PID `74821`: idb pulled
  `.build/ui-probe-evidence/astra-vod-range-probe.txt/vod-range-probe.txt`. It reports
  `deadline-token/rearm=true`, `update-before-wait=true`, existing cache/lookahead/coalescing/disjoint-seek/offline/exact-size and
  last-lease-revival checks passed. This is a deterministic production-source probe with injected file transport, not live Telegram VOD.
- Separate runtime blocker B01: after the probe, this existing Simulator process terminated with `EXC_BAD_ACCESS` in pinned TDLib
  `td::get_page_blocks_rich_message_media` → `RichMessage::parse` → `MessagesManager::parse_dialog` while loading its database.
  Report: `/Users/lev/Library/Logs/DiagnosticReports/BetterTG-2026-10-02-142322.ips`. The screenshot shows Home, so it is not a passing
  app-flow smoke. No database reset/removal was performed. Verify probes on an isolated Simulator and separately investigate this
  dependency/data compatibility failure; the original database remains unverified.

### Isolated range and renderer-feedback proof — 2026-10-02

- Isolated iPhone 17 Pro / iOS 26.5 Simulator `BetterTG Astra Audit`, `59EB535C-3610-41A2-AB68-53A9467DC24B`,
  avoids B01 without modifying the original database. Each run used
  `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B -- ARGUMENT` and idb.
  Login screenshots/hierarchies and live processes accompany the probe output; no account login or server mutation occurred.
- A01/A02 recheck at `37c8b44`, argument `-media-probe-vod-ranges`, PID `78859`: all existing range checks plus
  `deadline-token/rearm=true` and `update-before-wait=true` passed. Evidence:
  `.build/ui-probe-evidence/astra-isolated-vod-range-probe/vod-range-probe.txt` and
  `astra-isolated-vod-login-visible{.png,-hierarchy.json}`. The process remained alive after 89 seconds.
- A03 preserves `pause()`'s unconditional `setRate(0, time: .invalid)`, including cancellation of pending rate changes.
  `snapshotPublisher` deduplicates the full Equatable snapshot, retaining changes to clock/rate, generation, topology, queues,
  errors and finish state. The bounded asynchronous feedback probe receives exactly one settled paused snapshot.
- One SwiftFormat invocation covered `FFmpegSampleBufferRenderer.swift`; warning-free build:
  `.build/logs/xcodebuild/build-Debug-20261002-142824-79043-26845.log`. Independent diff review found no blocker.
- `-media-probe-vod-sample-buffer`, PID `79850`: `pause-feedback-events=1`, 24 video/101 audio buffers, stable pause,
  seek generation/preroll, stale drops, finish delivery, rate 1.5 and zero renderer errors passed. Output:
  `.build/ui-probe-evidence/astra-isolated-vod-sample-buffer-probe/vod-sample-buffer-probe.txt`;
  login screenshot/hierarchy: `astra-isolated-sample-buffer-login{.png,-hierarchy.json}`.
- `-media-probe-vod-ffmpeg-controller`, PID `80246`: pause/rate/offscreen intent, last-seek-wins, persistent rolling windows
  (11 windows, one open, zero rollover seeks), EOF, offline/retry/clamp and cleanup passed; finite ranges, zero full downloads
  and zero renderer errors. Output: `.build/ui-probe-evidence/astra-isolated-vod-ffmpeg-controller-probe/vod-ffmpeg-controller-probe.txt`;
  login screenshot/hierarchy: `astra-isolated-ffmpeg-controller-login{.png,-hierarchy.json}`. Process alive after 51 seconds.
  Fixture SHA-256: `685af512ee52d20c4aa20ef182d7d208df242d45b674f8e6fc2bbef91bfeb810`.
- These are deterministic production-source probes, not live Telegram message playback or system PiP proof. The controller
  fixture's slightly unequal track ends do not cover A04's materially different durations. B01 remains unresolved.
  Both Simulators remain booted; the smoke agent disconnected its owned idb session.

### Animated decoder worker repair proof — 2026-10-02

- Scope: A07 only. Preserve first-frame fallback, existing frame timing/cache behavior and C-handle ownership. A native-free
  initializer creates the actor; `prepare`, frame reads/resets and `isolated deinit` run on its dedicated serial executor.
  Setup cancellation/generation/path/asset checks and frame decoder identity reject stale completion, including same-path reuse.
  A05/A06 account/download ownership and A08 timing are intentionally unchanged and remain open.
- Worker commit `c5642bc5b7b75210a467519b8e314a1cbaa4c801` was reviewed and cherry-picked as `3917128`.
  Only `FFmpegAnimatedVideo.swift` and one DEBUG entry in `BetterTGApp.swift` changed. Worker SwiftFormat covered both files;
  warning-free build log is preserved in the primary checkout at
  `.build/logs/xcodebuild/worker-A07-build-Debug-20261002-143909-89115-12760.log`.
- Worker run on isolated Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS 26.5, PID `92196`, remained alive for 51 seconds
  on production login. Preserved evidence: `.build/ui-probe-evidence/astra-worker-a07/animation-worker-probe.txt`,
  `astra-animation-login.png` and `astra-animation-login-hierarchy.json` in that directory.
- Primary integration: one SwiftFormat call covered all four Swift files changed during the audit repairs (`0/4` changed).
  `./build.sh build` passed without warnings at `3917128`; log
  `.build/logs/xcodebuild/build-Debug-20261002-144312-3881-1967.log`. Independent delta review found no blocker.
- `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B -- -media-probe-animation-worker`
  launched PID `4465`. Fresh container `E53CD086-9694-41C8-89CD-F27E033BC0A3` output was written at
  `2026-10-02 14:43:47 +0400`; idb pulled it into
  `.build/ui-probe-evidence/astra-integrated-animation-worker/animation-worker-probe.txt`.
  Both runs report actual create/read/reset/destroy off-main, main-release/worker-destroy, delayed-setup cancellation,
  same-path reuse fencing, replacement readiness, preserved first frame and exactly-once teardown; five native reads.
- Integrated screenshot/hierarchy `astra-integrated-animation-login{.png,-hierarchy.json}` show the live production 2FA screen,
  not a chat/sticker flow. The user subsequently reported logging into the open Simulator; no credentials were entered by the agent.
  On resume, inspect current authorization/reachable chats before selecting authenticated smoke. This user update does not close
  B01 for the original database, prove sticker playback, or authorize another implementation slice now.

## Implementation ledger

| Priority | Flow | Telegram reference | TDLib API / model | Status and proof before revalidation |
| --- | --- | --- | --- | --- |
| P0 | Remove MobileVLCKit; local audio/video playback seam | `submodules/TelegramUniversalVideoContent/Sources/PlatformVideoContent.swift` at the pre-Liquid baseline | `downloadFile`, `updateFile`, `cancelDownloadFile` | **partial** — `LocalMediaPlayer` uses AVFoundation, gallery playback pauses offscreen and has thumbnail fallback, and downloaded Ogg/Opus audio is cancellably decoded by FFmpeg before AVPlayer use. A range-backed FFmpeg controller now emits owned BGRA video and interleaved float audio for generic VP9/Opus WebM without a full download, renders both tracks on one Apple media clock, and is production-routed through the persistent inline/fullscreen gallery owner. `./build.sh build` passes without warnings and `rg` finds no VLC dependency/import/API marker in `project.yml` or `BetterTG`. Persistent FFmpeg sessions span rolling windows and sample-buffer PiP uses the exact display layer; only active system PiP/device proof remains. |
| P0 | TGS stickers and animated/custom emoji | `AnimatedStickerFrameSource.swift` gzip/rlottie path, `AnimatedStickerNode.swift` lifecycle, and pre-Liquid `MultiAnimationRenderer.swift` / `EmojiTextAttachmentView.swift` | `MessageSticker`, `TextEntityType.customEmoji`, `getCustomEmojiStickers`, `downloadFile`, `updateFile` | **partial** — timeline/gallery TGS uses bounded zlib decode, pinned Lottie 4.6.1, synchronized loops, visibility pause, parsed cache, prefetch/cancel, and thumbnail fallback. Custom-emoji entities are batch-resolved by ID, mapped from arbitrary TDLib order, overlaid on exact TextKit glyph rects, keep the native glyph until first frame, and share TGS/WebP/WebM clocks/lifecycle. `./test.sh` passes; Telegram `tiny.tgs` decodes to valid 100×100@30 JSON; current idb smoke confirms ordinary/wrapped text and timestamps remain stable. No custom emoji exists in the reachable viewport, so visual rendering and `needsRepainting` substitution remain unproved/pending. |
| P0 | Animated WebP | `submodules/WebPBinding/Sources/UIImage+WebP.m`; Telegram only uses its static frame fallback | `StickerFormat.webp`, `File`, `downloadFile`, `updateFile` | **partial** — direct pinned libwebp 1.6.0 demux preserves frame timing, blend/disposal canvas and premultiplied alpha; timeline/gallery share a synchronized display clock, off-main decoder, 64 MiB frame/asset caches, full-file prefetch/cancel, visibility pause, and thumbnail fallback. `./test.sh` passes; the exact metadata path decodes upstream's 4,764-byte animated fixture as 990×1050, 8 frames/0.8 s, and the first BGRA frame proves alpha 0…255. Current `./run.sh` + idb launch/chat smoke is stable; visual playback awaits a reachable WebP sticker in simulator data. |
| P0 | WebM/VP9 alpha stickers and generic FFmpeg playback | `AnimatedStickerNode/VideoStickerFrameSource.swift`, `FFMpegMediaVideoFrameDecoder.swift`, `FFMpegAVFrame.m` | `StickerFormat.webm`, `File`, `downloadFile`, `updateFile` | **partial** — checksum-pinned FFmpeg 9.0 decodes the main VP9 stream plus Matroska `BlockAdditional` alpha stream, scales to BGRA, premultiplies alpha, and feeds synchronized timeline/gallery loops with off-main decode, 64 MiB caches, prefetch/cancel, visibility pause, and thumbnail fallback. GIF/non-Apple animation containers now route through the same renderer while MP4/MOV retain AVFoundation. The non-looping range decoder retains probe packets, decodes VP9+Opus on a named worker, copies borrowed C frames before callback return, trims seek preroll/sample tails to the exact requested interval, and supports supersession/cancel. Its renderer uses pooled IOSurface-backed BGRA buffers, packed Float32 PCM and one `AVSampleBufferRenderSynchronizer`, with bounded generation-aware queues and no `DisplayImmediately`. The rolling controller is production-routed for public, secret, streaming, non-streaming and already-cached WebM/Matroska videos while Apple containers stay on AVFoundation. `./build.sh build` and the gallery-owner idb probe pass; persistent cross-window decoder and sample-buffer PiP adapter probes pass; real-message visual proof and active PiP on a capable device remain. |
| P0 | Voice notes: Ogg Opus, waveform, record/lock/edit/send | `ManagedAudioRecorder.swift`, `OpusBinding/Sources/opusenc/opusenc.m`, `AudioWaveform.swift`, `TGModernConversationInputMicButton.m`, and pre-Liquid `ChatRecordingPreviewInputPanelNode.swift` | `VoiceNote`, `InputMessageVoiceNote`, `resendMessages`, `updateMessageSendSucceeded/Failed`, `downloadFile` | **implemented breadth** — capture is 48 kHz mono signed-16 PCM, rejects recordings below 0.5 s, produces an exact 100×5-bit/63-byte waveform, and sends only validated Ogg/Opus. Transactional send manifests survive registration/crash races, failed sends honor TDLib resend state, multiple drafts promote, and unsupported paid/alternate-reply states cannot silently resend. Telegram's 0.19 s hold/release, slide-cancel/lock distance+velocity ordering, pre-arm/system-cancel preservation, VoiceOver lock, and scoped bottom-edge deferral are implemented. Locked Stop-and-preview closes WAV segments, validates/merges exact PCM frames off-main, derives Telegram-normalized waveform samples, and atomically owns a revisioned editable draft. The UIKit island exposes Delete, Record More, Play/Pause, hollow seekable waveform, two continuously draggable/VoiceOver-adjustable trim handles, selected duration and Send. Trim metadata is revisioned and restored; selection is at least 1s/56pt, playback and seek clamp to it, releasing either edge previews the changed edge, and Resume presents destructive-trim confirmation. Any non-full trim is materialized to a new PCM revision before Record More or Ogg promotion, recomputing exact duration/waveform. Dedicated playback has reciprocal arbitration and scoped session release. Reply/interruption ownership, cancel/send/trim generations, manifest relocation, relaunch restoration and cleanup are covered. `./test.sh` passes; idb proves exact `142→202`/`304→254.14` handle travel, hollow seek, edge preview, confirmation Cancel/Continue, revisioned append, relaunch playback, and trimmed safe-Send ordering (`1.33104s` materialized before `encoded=true`) with unchanged timeline and empty stores after Discard. Remaining voice work is encoder-quality parity/polish, not a missing requested flow. |
| P0 | Video notes | `submodules/Camera/Sources/VideoRecorder.swift`, `CameraRoundVideoFilter.swift`, `VideoMessageCameraScreen`, `ResultPreviewView.swift` | `InputMessageVideoNote`, `InputVideoNote`, `sendMessage`, `resendMessages` | **implemented multi-segment breadth** — the writer serializes capture queues, gates pre-video audio, waits video+audio EOF, center-crops/orients and round-masks actual pixels, and validates network-optimized 400×400 H.264 High/CABAC ~1 Mbps + mono 48 kHz AAC MP4. Generation-scoped AVCapture requests microphone then camera, defaults front, rejects stale PTS, freezes device orientation per recording, cleans interruptions/background/audio ownership, soft-stops at `>59.5s`, and hard-clamps at 60s. UIKit composer tap toggles mic/video; the unchanged Telegram 0.19s arm, live/release distance+velocity ordering, pre-arm lock, system-cancel preservation and bottom-edge deferral route both modes. A child recorder keeps the composer gesture alive and shows the classic max-369pt round camera, 4pt progress, 44pt flip/flash, pinch zoom, front-screen/back-torch flash, holding/lock/cancel, locked Stop-to-preview and release-to-send. Live 1s-throttled front/back switching rejects queued old A/V, removes the capture timestamp gap from both tracks and encodes a six-frame/0.2s dissolve instead of only smoothing the preview. Single-result preview loops muted and can play/pause/delete/send; TDLib promotion uses `InputVideoNote` and preserves the snapshotted reply. Atomic manifests own adopted MP4s across crash/chat close, reconcile outcome-before-registration, expose safe no-paid retries while keeping unsupported failures discardable, and clean success/discard/permanent delete. The ordered-segment foundation owns stable-ID MP4 segments, atomically persists revisioned global trim, composes video/audio on identical boundaries, samples exactly 13 full-composition thumbnails, materializes a zero-start 1…60s export, and preserves a 0.5…1s first result for Record More. `LocalMediaPlayer` retains the full `VideoNoteCompositionResult` snapshot lease, applies `forwardPlaybackEndTime`, exact last-target-wins seeks and loops from the global trim lower bound without rebuilding the item. UIKit Record More is visible only below 59s, starts hands-free, ignores sub-0.5s Stop, appends in order while clearing prior trim, uses aggregate 59.5s soft/60s hard limits and non-destructively restores preview on capture failure. The UIKit strip decodes exactly 13 indexed JPEGs off-main with cancellation, keeps them stable across trim revisions, and overlays adjustable global handles with an epsilon-safe exact 1s minimum. Live drag keeps handles active, pauses and exact-seeks only the changed edge; terminal save blocks other actions, persists once from the captured revision and resumes from the lower bound using current playback intent. Composition playback appears before thumbnails, then advances monotonically from empty to repeated frame 0 to all 13 exact frames without disturbing trim state. Circle tap and VoiceOver activation toggle mute separately from Play/Pause; a visible mute badge and scoped playback audio session track every-loop re-mute and reciprocal Media takeover. Navigation/relaunch restores the originating chat’s draft and stored reply; final send rejects aggregate selections below 1s, materializes the selected range and transfers the durable origin explicitly. A transformed time-0 frame from that materialized MP4 becomes a quality-0.4, ≤320px, <200KB JPEG `InputThumbnail`; real-image/dimension validation falls back to nil, while valid JPEG ownership persists beside the MP4 through retry/relaunch and terminal cleanup. Recording→send adoption is idempotent by durable origin ID and adopt+begin holds one actor lease. Runtime reservations cover draft/origin/file aliases; terminal cleanup first persists a relaunch-safe tombstone, confirms recording-manifest deletion, then removes send authority. Any failure leaves both durable authorities for retry, including missing-media and registered-success recovery. Timeline video-note bubbles are circular, cancellably downloaded, thumbnail-backed, offscreen-paused and locally playable with reciprocal audio arbitration; secret notes call `openMessageContent` before hold-to-reveal. `./test.sh`/`./run.sh` pass. Probes prove 1.0s A/V, round/orientation pixels, concurrent drain, pre-video audio, crossfade/audio-retime, limits/cancel, decoded segment/PCM order, exact thumbnail times, global trim, legacy manifests, same-origin dedupe/barrier, atomic enqueue, durable/corrupt-thumbnail handling, removal-tombstone relaunch and send success/failure races. idb proves voice↔video toggles, real permission/camera-unavailable routing and exact cleanup; Simulator has no camera, so hardware capture/flip/flash remains unproved. |
| P0 | VOD before full download, range seek/refetch, PiP | pre-Liquid `ChunkMediaPlayerV2.swift`, `ChunkMediaPlayerDirectFetchSourceImpl.swift`, and `UniversalVideoGalleryItem.swift` native PiP lifecycle | `downloadFile(offset:limit:)`, `getFileDownloadedPrefixSize`, `getFile`, `updateFile`, `cancelDownloadFile`, `updateDeleteMessages` | **partial — inline/fullscreen native VOD + owner-scoped PiP + production FFmpeg range playback**: each injected TDLib client owns its file coordinator and private update streams. Reads cap at 256 KiB, probe 512 KiB, fetch 2 MiB, reuse overlap, cancel disjoint/stale generations, distinguish cached/buffering/offline/retryable/terminal state, and never treat `expectedSize` as EOF. Refcounted leases share a source and only the last current lease cancels. FFmpeg 9 custom AVIO uses a 64 KiB buffer, exact checked seek/size callbacks, named blocking threads, shared raw-PTS A/V timeline and ≥10s packet lookahead. One persistent demux/codec/SWR session now spans soft rolling horizons within each seek generation; crossing frames are emitted whole, sparse per-track packets use a globally ordered bounded FIFO, pause retains the session, and seek/offscreen/cancel replace it terminally. Decoder reads share the source's cancellable serialization gate, retry transient displacement, retain stream-probe packets, cap allocation/read/packet work, decode bounded windows to owned BGRA and 48 kHz interleaved float frames, drain codecs/SWR at EOF, clip output to `[seek,target)`, and terminate deterministically on supersession/cancel. Apple-decodable non-secret MP4/M4V/MOV uses strict custom-scheme `AVAssetResourceLoader` metadata and serialized ≤256 KiB reads; `LocalMediaPlayer` retains the asset/delegate/lease, explicitly manages a 1s playable threshold and 10s forward buffer, preserves 0.5×–2× rate, and adopts raw AVKit pause/play/rate/EOF intent without rebuffer restart races. WebM/Matroska routes through the rolling sample-buffer controller for range-capable public media and through full-download-then-FFmpeg for secret/non-streaming media; completed files re-enter the same FFmpeg backend instead of AVPlayer. Fullscreen gallery preserves start time and exact thumbnail until first frame, exposes generation-safe fallback/Retry plus a full-width UIKit blur footer with play/pause, ±15s, duration, disjoint loaded ranges, terminal scrub, mute, rate, auto-hide and VoiceOver seeking. Serialized loader and typed FFmpeg failures distinguish buffering/offline/retrying/terminal failures; generation-guarded publisher bindings prevent canceled or replaced backends from publishing stale state. Offline/timed-out VOD preserves the playhead and retries through a fresh range session without forcing a full download, while terminal decode failures retain generation-safe full-download fallback. A message-scoped owner now retains the exact view/layer/player/resource-loader/TDLib lease across standalone timeline, grouped album tiles, fullscreen and PiP. Inline videos are muted aspect-fill with controls hidden; only the greatest-visible-area owner is active, using the real standalone or mosaic-tile frame, and inactive owners defer all local/VOD/full playback loading. Every album video owner is transferred into gallery as one account-scoped set, preventing a second neighbor player/lease when paging, and every borrowed owner returns to its exact tile. Generation-scoped attachment tokens reject stale cell callbacks after reparent, diffable pruning uses current visible child message IDs, borrowed dismissal/PiP stop returns the same item and playhead, and offscreen owners pause then release. Standalone and grouped media open and close through UIKit-only exact source transitions: the exact bubble/tile is captured synchronously before owner reparent, clipped through every ancestor into explicit window coordinates, rasterized without play/status overlays, and animated into the aspect-fit gallery rect with its corner mask. Dismiss resolves the current selected stable ID afresh; stale/reused/offscreen/deleted/PiP targets fade, generation-safe cleanup cannot mutate a reused cell, and owner return happens only after successful transition completion under the hidden source. Rotation re-centers the same selected message. Timeline, album and prefetch thumbnail paths never use the whole video as fallback. Gallery neighbors remain bounded to central ±1. Native `AVPictureInPictureController(playerLayer:)` is manual, hidden for secret/looping/noncentral/unready/unsupported media, and owned outside cells. A token-scoped movie-playback audio session restores partial failures without deactivating another owner, hands raw controls to external transport, and relinquishes on Media takeover. The singleton transfer coordinator retains active PiP across gallery dismissal, re-presents the exact account/chat/message with the same owner/session, waits for presentation teardown, and restores the exact item without flash. Pending start and stop have bounded generation/timeouts; coordinator authority is retained while AVKit remains active. Permanent deletes arrive on the injected client's private stream, revoke matching chat/message PiP and restoration, while deleted noncurrent neighbors update in place. `./build.sh build` passes without warnings. The SHA-pinned simulator decode probe emits 24 VP9 frames and 96,000 stereo-Opus sample frames with monotonic timestamps, exact post-seek output, codec/SWR tail drain, finite `downloadFile` ranges, zero full downloads, supersession and cancellation. The gallery-owner idb probe additionally proves `ffmpeg-route=true`, exact controller/playhead continuity, preserved offscreen intent, finite ranges, cleanup and the unchanged native MP4 owner path. Existing simulator proofs also cover partial cold playback, local/external controls, range cancellation, loaded ranges, offline retry, exact inline→fullscreen→inline view/item/playhead continuity, zero transfer-cancel delta, terminal lease cancellation, exact clipped/fresh standalone and album-tile geometry, single active tile arbitration, dismissal retention, delete revocation and readiness gating. This simulator reports `pip-supported=false`, so active PiP/background/system-control/restore behavior still requires a PiP-capable device proof. Persistent FFmpeg sessions and sample-buffer PiP transport/lifecycle are simulator-proved; actual system PiP/background/restore remains a physical-device proof gap. Livestreaming is excluded. |
| P0 | Exhaustive message content and actions | pre-Liquid `ChatMessageReplyInfoNode`, `ChatMessageForwardInfoNode`, `ChatMessageSelectionNode`, `ChatMessageSelectionInputPanelNode`, `PeerSelectionController`, contact/map/poll/action nodes, and `ServiceMessageStrings` | all 104 TDLib 1.8.66 `MessageContent` cases; `MessageReplyTo`, `TextQuote`, `MessageForwardInfo`, `ForwardSource`, `getMessageProperties`, `forwardMessages`, `searchChats`, `searchChatsOnServer`, file/poll/edit/copy/reply/delete APIs | **partial — exhaustive catalog + core cards + reply provenance + real Forward/select**: the 104-case no-default catalog drives timeline/chat-list summaries, captions and accessibility. UIKit covers attachments/albums, contact, MapKit location/live expiry, poll/quiz, emoji/dice fallback, service and unsupported rows. Reply/forward metadata preserves chat-scoped IDs, source/origin, inline and ID-zero fallback, thumbnails, PSA, manual quote text/UTF-16 position and unavailable/story state. Manual quote authoring emits a bounded entity-safe `InputTextQuote`; external/story overrides survive text/photo/voice/video/draft paths. Classic reply expands 5→50 lines before navigation, exact destination text highlights after `willDisplay`, and forward taps prefer source message/chat with account-safe cross-chat routing. Context Forward expands the complete album; Select owns stable outer IDs while every action expands, de-duplicates and strictly sorts real child IDs with a 100-message cap. The classic UIKit mode uses full-row taps, a 28pt check at x=6, 42pt incoming-only shift, message-count navigation state, full-width safe-area blur actions and exact per-child TDLib capability refresh. Multi-delete revalidates revoke scope. The full-screen UIKit Forward picker supports Saved/main/archive/server discovery, multiple ordinary chats and multiple explicit topics in the same forum, sender/caption modes, secret-copy rules, per-content/topic permissions, account generations and partial outcome safety. Builds are warning-free; deterministic device proof is recorded below. Remaining P0: recipient comment/forward-draft transition, drag-select/autoscroll, positional null-result support in pinned TDLibKit, link previews/spoilers, resolved service actors/pinned targets, poll voters/media, insertion-aware/slot dice and rich/game/story/checklist UI. |
| P0 | Message reactions | pre-Liquid/current `ReactionButtonListComponent`, `ChatMessageReactionsFooterContentNode`, `ChatMessageBubbleItemNode` and `ChatController` reaction flow | `MessageInteractionInfo`, `MessageReactions`, `getMessageAvailableReactions`, `addMessageReaction`, `removeMessageReaction`, `updateMessageInteractionInfo`, `updateMessageUnreadReactions`, `readAllChatReactions`, `readAllForumTopicReactions` | **implemented ordinary/explicit-topic breadth** — UIKit renders TDLib emoji/custom-emoji reactions as sorted 30pt chips with 20pt icons, exact 6pt wrapping, selected/unread state, compact counts, incoming/outgoing/center alignment, VoiceOver labels/actions and offscreen-paused TGS/WebP/WebM custom emoji. Existing album reactions stay on the representative bubble. Context React can originate the first reaction through a non-Premium standard-emoji picker. Every add re-fetches authoritative message availability, excludes per-item Premium and paid/Stars types, honors unavailability and chat maximum count, while a chosen non-paid reaction remains removable under new restrictions. Generation-safe optimistic state rolls back failures; normal-user interaction/unread plus chat permission/availability updates reconcile under captured account/client guards. Explicit-topic rendering/picker/mutation validates the current `ChatLocation`, and acknowledgement uses `readAllForumTopicReactions`. Deferred polish: custom-emoji add grid, reactor list/recent avatars, disappearing-chip animation and live server mutation smoke. |
| P0 | Pinned messages | pre-Liquid/current `ChatInterfaceStateContextMenus`, `ChatControllerLoadDisplayNode`, `ChatPinnedMessageTitlePanelNode` and message-window navigation | `Message.isPinned`, `MessageProperties.canBePinned`, `getChatPinnedMessage`, `pinChatMessage`, `unpinChatMessage`, `updateMessageIsPinned`, `updateDeleteMessages` | **implemented ordinary-chat newest-pin breadth** — initial and refreshed state comes only from account/client/generation-fenced `getChatPinnedMessage`; only confirmed 404 clears while transient failures retain the last authoritative banner. Permanent non-cache deletes and authoritative unpins clear before refetch, edits/content refresh the preview, and stale mutation/fetch/animation completions are revision-gated. Context Pin/Unpin uses freshly fetched `canBePinned`, one chat-serialized optimistic transaction and exact Saved/private/group/channel notification/scope modes. A classic full-width 50pt UIKit chrome-material banner sits below navigation, shares spoiler-safe reply thumbnail extraction, locally hides by newest message ID, resurfaces for a newer ID, preserves the inverted timeline offset, and taps through existing history-window navigation. Dynamic Type is capped to the fixed panel geometry and VoiceOver exposes separate Open/Hide controls. Forum/view-as-topics/direct-message groups, albums and sending/service messages are explicitly gated. Proof is recorded below. Deferred parity: nearest-visible pin rotation, pinned-only list/pagination, admin undo and older-pin warning detail. |
| P0 | Forum topics: list, explicit writes and all-messages timeline | pre-Liquid/current `ChatListNodeLocation.swift`, `ChatMessageItemImpl.swift`, `ChatMessageDateHeader.swift`, `ChatInterfaceStateInputPanels.swift`, `ChatControllerMediaRecording.swift` and `ChatControllerLoadDisplayNode.swift` | `MessageTopic`, `ForumTopic`, `getForumTopics`, `getForumTopic`, `getChatHistory`, `getForumTopicHistory`, `updateForumTopicInfo`, `sendMessage`, `sendMessageAlbum`, `setChatDraftMessage`, `sendChatAction` | **partial — explicit-topic breadth + production all-messages composer routing** — runtime identity is `(accountID,clientID,chatID,MessageTopic?)`; exact topic list/history/search/update and immutable explicit-topic write context remain. `Chat.viewAsTopics` authoritatively selects topic list (`true`) versus base history (`false`). Base history renders stable adjacent-topic headers, preserves raw pagination/album identity and visible message+pixel anchors, and excludes headers from message-only behavior. Text/photo/edit use discovered General without reply or the replied message's exact topic, reject closed-topic replies, and always store/clear the route draft with `topic:nil`. Voice/video now snapshot that same destination+reply at recording start, persist it separately from the base draft key through preview/relaunch/retry, revalidate live metadata/permissions before enqueue, and route record/upload/cancel actions through the frozen topic. Warning-free build proof is recorded below. |
| P0 | Topic composer durable media identity | pre-Liquid/current `ChatInterfaceState.swift`, `ChatControllerMediaRecording.swift` and thread-scoped interface-state ownership | `MessageTopic`, `InputMessageVoiceNote`, `InputMessageVideoNote`, `updateMessageSendSucceeded/Failed` | **implemented write foundation** — `ChatDraftKey(accountID,chatID,MessageTopic?)` remains the on-disk route/draft owner across voice/video recording, preview, send, retry and outcome reconciliation, while the four version-tolerant manifests persist a separate immutable `sendTopic` for all-messages General/reply routing. Runtime-only TDLib client IDs remain excluded. Stores restore/deduplicate/enqueue/discard by route destination; enqueue and chat actions use the frozen send topic and reply, with live closed/permission checks and account/client fences. Outcome files use draft UUID rather than colliding chat/message IDs. A one-time account-registry migration snapshot may claim unambiguous legacy base drafts; legacy records without `sendTopic` remain valid but cannot be guessed into an all-messages destination. Runtime proof is below. |
| P0 | Forum-aware Forward destinations | pre-Liquid/current `ChatControllerForwardMessages.swift` and `PeerSelectionController.swift` | `getForumTopics`, `getForumTopic`, `forwardMessages(topicId:)` | **implemented breadth** — destination identity is `(chatID, MessageTopic?)`, so ordinary chats and multiple topics in one forum coexist in one selection. Forum rows drill into an exact-cursor UIKit topic picker; closed/hidden topics require creator/manage-topics authority and every content permission is rechecked at delivery. Source account/topic membership is fetched both at preparation and immediately before mutation. TDLib results must have exact count/chat/topic; transient forum metadata failures disable rather than fall through to General. Classic full-width material headers, plain Back and table-header search avoid iOS 26 floating glass. Live idb proof selected a real forum topic locally without pressing Forward. |
| P0 | Composer and send/delete transitions | pre-Liquid chat input panel and message transition paths | `FormattedText`, `InputMessageContent`, `sendMessage`, edit/reply/delete APIs | **partial** — one UIKit floating blur island owns formatted text, emoji insertion, non-Premium installed stickers, saved GIFs, photos/camera, security-scoped multi-file documents, reply/edit and voice/video states in ordinary, explicit-topic and all-messages chats. Sends serialize to prevent duplicate rapid-tap delivery and clear UI only after TDLib acceptance. Real UIKit snapshots of visible reply/text/photo/album/document/voice/video-preview-or-retry sources follow temporary→final IDs and fly into canonical insertion; viewport anchoring remains independent. Sticker/GIF sends use exact permission/topic/reply contexts, captured draft cleanup, account-fenced search, offscreen-paused/cancelled media and no Premium/Stars results. Voice/video retry authority and document upload leases survive UI teardown. Full-bubble deletes fade+slide then collapse under a surviving anchor; no dust/particles. Remaining: public inline-GIF search, custom-emoji authoring and forward comment/draft. |
| P1 | Profiles, shared media, fullscreen gallery | pre-Liquid/current `PeerInfoScreen.swift`, `PeerInfoAvatarListNode.swift`, `PeerInfoPaneContainerNode.swift`, `PeerInfoScreenOpenMessage.swift` and gallery controllers | peer/full-info/status/title/photo updates; `getUserProfilePhotos`, `getBasicGroupFullInfo`, `getSupergroupMembers`, `getChatAdministrators`, `getChatMember`, `getMessageProperties`, topic/history APIs, `downloadFile`, `forwardMessages`, `deleteMessages`, `setName`, `setBio`, `setChatTitle`, `setChatDescription`, `setChatMemberTag`; message/file APIs | **partial — live UIKit profile + shared/avatar galleries + management/actions** — account-fenced user/bot/self/group/channel profile exposes live title/status/bio/usernames/phone/member/photo state and Media/Files/Links/Audio. Separate Members/Admins lists retain server order and roles, paginate raw supergroup offsets, react to membership/full-info changes and preserve a visible-row anchor; permission-gated self/chat Edit uses changed-only sequential writes, live cached visibility and exact pre-write member-rights revalidation. User rows open a standalone tag editor whose fresh self/other-member authority matrix, stale-baseline conflict check and awaited write follow current Telegram behavior without coupling tags to administrator rights. Shared media retains the profile under exact-source append-paged gallery with cancel-safe pan, unified video chrome, scrollable formatted/spoiler-safe captions and authoritative totals. Gallery Open in Chat captures the selected identity, re-fetches it through the captured client, revalidates account/client/topic through fade-dismiss completion, then routes into the source timeline without competing reverse transitions. Save and system Share now share one original-resource export boundary with fresh copy-protection checks, full TDLib download, account/generation fences and managed temp ownership; Photos receives signature-validated still images/GIF/MP4 and WEBP sticker frame PNG without moving TDLib cache files. Forward reuses the production topic/destination/comment picker and offers selected-item versus authoritatively bounded whole-album semantics. Delete intersects fresh per-ID modes, repeats pre-write authority, commits one batch and coalesces all-media permanent updates into one terminal fade without returning deleted playback/PiP owners. Header avatar opens a real-`ChatPhoto` gallery with user/bot/self role-aware raw-offset history, group/channel current full-info photo, exact item+file transition, zoom and no-flash central muted video loop. Generic Saved Messages self now preserves upstream title/blank-status/action semantics while rendering the captured account's real avatar and gallery instead of the Saved glyph. Typed peer/full-info bursts coalesce into one render; generation fences prevent stale `getChat`/full-info resurrection; role signatures reconcile populated avatar galleries without dismissing them. Warning-free proofs are below. Remaining: promote/demote/remove management tools and exhaustive profile actions. |
| P1 | Multiple accounts | Telegram account manager behavior without copying Postbox | separate TDLib clients and databases, authorization state, `logOut` | **partial — existing account breadth, isolation unverified** — add/auth/switch/remove/logout and client/storage paths already exist. Revalidate their production lifecycle and event/subscription ownership; animation A05/A06 and voice A13 expose cross-flow isolation gaps. Do not implement a second account shell from the old queued label. |
| P1 | Chats, folders, archive, search, edit/reorder | pre-Liquid `ChatListItem.swift`, chat list/filter controllers | chat lists/positions/folders, pin/mute/read/delete/clear/draft APIs | **partial** — main/archive/custom-folder lists and paging already exist; folder tabs are classic full-width material, and chat cells now use contiguous Telegram geometry with date, delivery, unread/mute/pin state and account-backed actions. Remaining: edit/reorder/include/exclude completeness, clear history/draft parity, archive reveal gestures, richer delivery/typing states and mutation account fencing. |
| P1 | Timeline stability and performance | pre-Liquid/current `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift` history/header behavior | `getChatHistory`, `updateNewMessage`, `updateDeleteMessages`, file updates | **partial** — stable message/album/topic/date IDs, raw-history pagination cursor, cross-page album merging, message-only prefetch/read/selection and visible `messageId + pixelOffset` restoration cover structural snapshots. Composer/keyboard insets, object-driven and autonomous cell self-sizing, bulk reconfigure, Dynamic Type and rotation now capture the same anchor or latest edge; mutation depth discards stale deferred anchors and never fights active dragging. Every chat emits one stable localized date row per day with exact date→topic ordering. Remaining proof/gaps: a live pagination/album seam, software-keyboard-attached runtime proof and eliminating residual metadata work from the main actor. |
| P2 | Classic shell/navigation polish | pre-Liquid navigation/tab bars, `ChatListFilterTabContainerNode.swift` and `ChatListItem.swift` | n/a | **implemented classic shell/list breadth** — the bottom folder bar is one edge-to-edge `systemChromeMaterial` surface through the safe area; its scrollable tabs use the pre-Liquid three-point selected line instead of an inset lens/capsule. Context menus use ordinary `systemMaterial` blur and classic corners. Chat-list cards are replaced by contiguous 76pt full-width rows with 60pt avatars at x=10 and separators from x=80. Source search finds no `UIGlassEffect`, `glassEffect` or `cornerConfiguration`. Warning-free build and real-state idb proofs are below. Remaining P2: systematic audit of secondary navigation/search/action surfaces. |

## Checkpoint

- Current handoff: the started repairs are committed (`37c8b44`, `3005369`, `3917128`); the reusable prompt and checkpoint are
  updated. Stop until explicit resume; do not claim the broad parity goal is achieved. A01/A02/A03/A07 passed warning-free
  builds and isolated deterministic Simulator probes. Voice A11–A14 and text A10 are source-confirmed, not runtime-proved.
  B01 still blocks the original Simulator database; the user reports login on the open Simulator for subsequent smoke.
- Latest integrated production SHA: `3917128`. Final warning-free build:
  `.build/logs/xcodebuild/build-Debug-20261002-144312-3881-1967.log`. Production/dependency scan over `project.yml`, `BetterTG`,
  `BetterTGNotificationService` and `Packages` has no VLC, SwiftUI/hosting/representable or Liquid Glass markers.
  The prompt/document delta received an independent read-only review. Neither clean build nor this marker scan closes the audit.
- The auxiliary `astra-animation-worker/BetterTG` worktree is clean and its commit is integrated; proof files were preserved
  in the primary checkout. App-managed archival was refused because the worktree is protected by a pinned task/workspace.
  It was left intact; no forced cleanup was attempted. The owned idb session was disconnected; Simulators remain booted.
- Initial documentation-only validation at `6b417da`: `./build.sh build` passed without warnings on Xcode 26.6; log
  `.build/logs/xcodebuild/build-Debug-20261002-141016-42207-16861.log`. The missing ignored `Secret.swift` was restored from the
  main checkout for the build and is excluded from the commit. Documentation-only peer review passed; no Swift source edits or
  new runtime smoke were performed. This build does not close any implementation-audit row.
- Exact next slice after an explicit resume: A11, preserve voice preview/trim/reply on Back and permission loss without changing
  explicit Delete semantics; verify Back/reopen/relaunch and keep input files owned. Then A12/A13 outcome route/provenance and
  A14 finalization reservation, followed by the remaining A04–A10 findings. B01 needs a data-preserving TDLib investigation.
  Continue video-note, owner/PiP, complete MessageContent/actions, composer/timeline, profile/gallery and account/list/shell audit
  coverage. Retain completed range/renderer checks; do not restart source review unless code/dependencies change.
  New feature breadth remains behind the audit gate.
- Last pre-audit feature slice: `7b0699d` member/admin user rows open a standalone UIKit member-tag flow with fresh
  actor/target authority, exact baseline conflict detection, awaited `setChatMemberTag`, account fences and post-success list reload.
- Timeline invariants to revalidate: raw TDLib pagination owns the cursor; `mediaAlbumId` owns grouped identity across pages; heterogeneous
  message/date/topic items rebuild from canonical state; only messages participate in behavior; every structural apply restores a visible
  message + exact pixel offset. Date→topic ordering and significant-time/locale reconfiguration follow Telegram's header spaces.
- Historical verification: warning-free Xcode 26.6 build `.build/logs/xcodebuild/build-Debug-20260831-153759-82885-28094.log`; focused
  Telegram/API and post-reload-fix delta reviews reported CLEAN. PID `83599` completed the non-mutating member-tag smoke; Simulator
  was left booted. These results are not a fresh whole-implementation audit.
- Historical proof blockers to reassess: the reachable account lacked member-tag authority; the denial path was runtime-proved,
  authorized editing/writes were source-reviewed/build-proved only. No safe reachable forum had `viewAsTopics == false`, the software
  keyboard stayed hidden after first-responder taps, and idb omitted context-menu actions. Active PiP and camera capture need capable
  hardware. Record current availability and continue independent checks without upgrading blocked proof to passed.
- Deferred feature candidate after the audit: promote/demote/remove member-management tools. Keep rights mutations independent of
  member tags; confirmed higher-priority audit findings take precedence.

## Historical implementation slices

### UIKit peer profile and shared-media slice

- **P1 flow:** pre-Liquid/current peer-info header, pane and open-message behavior from `PeerInfoScreen.swift`,
  `PeerInfoHeaderNode.swift`, `PeerInfoPaneContainerNode.swift` and `PeerInfoScreenOpenMessage.swift`, adapted to UIKit + Combine +
  TDLibKit without Telegram infrastructure.
- Implemented: chat title/avatar entry; user/bot/self/basic-group/supergroup/channel identity; full-info bio/description,
  username/phone/member details; Message/Search actions; one scrollable Dynamic Type header; Media/Files/Links/Audio tabs; exact current
  `MessageTopic` query scope and open-in-chat route; stable deduplicated pagination; empty and later-page retry without losing the cursor;
  account/client fencing; cancellable grid thumbnail download with redisplay restart; accessibility labels and intrinsic action height.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-105649-495-22414.log`; focused source/delta review clean. Runtime PID
  `840` exposes Profile/Back, exactly one `4 members`, 56.67pt intrinsic Message/Search actions, the four-tab group, 12 visible Media
  tiles, `No shared files`, real Link rows and a real `.m4a` Audio row. The exact Media→Files→Links→Audio path remains alive after fixing
  UIKit diffable snapshot reentrancy, and Back returns to the group chat. Evidence is under
  `.build/ui-probe-evidence/profile-shared-media-*`; no media or server mutation was selected.
- Deferred at this slice (see subsequent profile/gallery slices): avatar/video header history and fullscreen entry; edit/member/admin
  controls; shared-media selection/actions; live metadata reconciliation; gallery caption, gesture, rotation and complete
  save/forward/delete/open-in-chat/video-control parity.

### Profile shared-media gallery slice

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

### Unified fullscreen gallery chrome slice

- **P1/P2 flow:** current/pre-Liquid gallery single-tap chrome and video-control coordination, adapted to UIKit recognizers without
  importing Telegram transition/gesture infrastructure.
- Implemented: controller-owned `chromeIsVisible`; edge-to-edge pager behind a full-width safe-area blur overlay; photo single tap
  dynamically waits for nested double-tap zoom; controls/retry/seek touches are excluded; selected video disables its private tap and
  reports controls visibility/auto-hide through its playback owner to the same footer/status state; page/reuse/dismiss/PiP bindings are
  explicit. VoiceOver can never leave Close/Share hidden, hidden footer leaves AX, Reduce Motion is honored, and accessibility Escape
  closes. Video controls stay exactly above the 50pt footer plus bottom safe area instead of being obscured by the overlay.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-113041-8640-9218.log`; final delta review CLEAN. PID `8944` proved
  photo chrome `visible→hidden→visible` (`402×874` media when hidden), video single-tap exposing seek/back/play/forward/mute/rate plus
  `gallery-close`/`2 of 30`/`gallery-share`, playing auto-hide removing both control groups from AX, and Close returning to Profile.
  Screenshot: `.build/ui-probe-evidence/profile-gallery-unified-video-controls.png`; no Share or server mutation occurred.
- Deferred: deliberate double-tap/pinch and VoiceOver-status runtime toggles.

### Guarded interactive gallery dismissal slice

- **P1 flow:** Telegram current/pre-Liquid down-swipe gallery dismissal, adapted to the existing exact-source UIKit animator through
  `UIPercentDrivenInteractiveTransition` without importing Telegram gesture/transition infrastructure.
- Implemented: one-finger, positive-y, 1.2× direction lock; exact centered-page requirement; minimum photo zoom with no zoom bounce or
  deceleration; horizontal pager cooperation; temporary pan/pinch suspension only after begin; touch exclusion for footer, every
  `UIControl`, visible video controls and Retry; active seek/PiP/start/stop/retention rejection. Progress is translation-driven; 28% or
  900pt/s finishes, otherwise cancel restores chrome, modal AX isolation, pager/zoom gestures and pending page/delete updates. Playback
  owners release only from the animator's completed commit. Account switch force-finishes the interaction and pops the profile from the
  transition completion; an unexpected cancel uses a terminal nonanimated fallback instead of leaving an invalid gallery visible.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-114920-12706-5954.log`; final delta review CLEAN. PID `12991` proved a
  slow 70pt/1s down-pan cancels with only gallery AX and restored `gallery-close`/`1 of 30`/`gallery-share`; a 450pt/0.4s down-pan finishes
  at Profile with the exact 131×131 source tile; horizontal swipe still reaches `2 of 30`; up-swipe remains in gallery. No Share or
  server mutation occurred; Simulator remains booted.
- Deferred: deliberate zoomed-photo, live seek, active PiP and external account-switch gesture rejection on capable/runtime states.

### Fullscreen gallery caption and total-count slice

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

### Real profile avatar gallery slice

- **P1 flow:** current/pre-Liquid `PeerInfoAvatarListNode` → `AvatarGalleryController`, adapted to UIKit and native TDLibKit models rather
  than synthetic timeline messages.
- Implemented: header 96pt image/button AX only when a real effective/full photo exists; a true placeholder remains image-only. User/bot
  payload preserves effective/personal/normal/history/trailing-public roles with stable `ChatPhoto.id` dedupe, keeps raw history offset
  independent of extra role entries, inserts later 100-photo pages before public fallback and exposes footer Retry. Group/channel use the
  only available TDLib source, `BasicGroupFullInfo.photo` / `SupergroupFullInfo.photo`; `ChatPhotoInfo.big` is a static fallback only and
  never fabricates an animation. A separate UIKit pager keeps stable photo IDs/current page through rotation, exact-animates the whole
  circular header only for the current item and fades historical items. Captured-client synchronous JPEG/MP4 requests have per-file
  generations and no global update bus; 96MB/cost-limited decoded cache; static image remains until `AVPlayerLayer` ready; animation seeks
  to `mainFrameTimestamp`, loops muted only central, pauses/resets offscreen; nested pan activates only above 1× while pinch/double-tap
  remains available. Late network completions require current account, visible/top profile and no competing presentation.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-124706-24968-7861.log`; final source/delta review CLEAN. Runtime PID
  `24630` exposes `<group> profile photo` as 96×96 button, opens real `Profile photo, Mar 19, 2026` in the modal pager with plain
  `avatar-gallery-close`, then restores the exact 96×96 source. Screenshot:
  `.build/ui-probe-evidence/profile-avatar-gallery-final.png`; no mutation occurred.
- Blockers/deferred: current safe group has one static photo, so user >100 pagination, animated avatar loop and zoom gestures are not
  runtime-proved. TDLib cancellation is global per client/file; without a cross-consumer lease coordinator, offscreen deliberately
  cancels only local await/decode/playback work and lets active transport finish into TDLib cache rather than cancel another consumer.

### Generic self avatar source slice

- **P1 flow:** Telegram current/pre-Liquid generic self info opened from Saved Messages, explicitly distinct from Settings/My Profile.
- Implemented: self is captured once only when a non-nil account user ID equals the peer. Generic self title remains `Saved Messages`,
  presence is blank, redundant Message is hidden, and Search/Edit remain. `ProfileAvatarView` can render the real self peer file over the
  Saved glyph only for this captured profile context. The explicit image path owns account/client/user identity, waits for the full file
  through that client, uses no global `updateFile` bus, never cancels shared TDLib transport, and suppresses every callback after switch.
- Header source follows effective `User.profilePhoto` then main `UserFullInfo.photo`; self `personalPhoto` is ignored and `publicPhoto`
  never becomes current. Gallery ordering is effective current → distinct normal/history → distinct public last. Raw history offsets stay
  server-owned, extra-role count is separate, and pages insert before public without moving the selected item. Transition to/from the
  header requires both exact photo ID and rendered file ID; otherwise it fades. Main/personal/public role signatures trigger a full-page
  reconcile that preserves a historical selection; reconciliation, pagination and initial open have independent UUID-owned task slots.
  An authoritative empty set closes/resets the pager instead of preserving stale media.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-152230-76740-9666.log`; final upstream/API/task-race review CLEAN.
  PID `74705` exposed the real cat avatar as a 96×96 `Saved Messages profile photo` button, exact `Saved Messages` title, no status and no
  Message action; Search/Edit and shared tabs remained. It opened real `Profile photo, May 10, 2023` with `avatar-gallery-close` and no
  mutation. Final build PID `77080` launched on the still-booted Simulator. Evidence:
  `.build/ui-probe-evidence/profile-self-avatar-source.png` and
  `.build/ui-probe-evidence/profile-self-avatar-gallery.png`.
- Runtime blocker/deferred: this account exposes one current profile-photo item, so >100 pagination, distinct public fallback, live role
  replacement, authoritative empty close and concurrent request invalidation are source-reviewed/build-proved rather than live-mutated.

### Live profile metadata slice

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

### Profile member, administrator and edit controls slice

- **P1 flow:** current/pre-Liquid peer-info member/admin panes and creator/administrator edit gates, adapted to UIKit diffable tables and
  TDLibKit without Telegram account or list infrastructure.
- Implemented: a separate intrinsic management row with Members, Admins and permission-gated Edit. Basic groups use the complete
  `BasicGroupFullInfo.members`; supergroups/channels expose Members only under `canGetMembers` and advance pagination by raw
  `ChatMembers.members.count`; Administrators use `getChatAdministrators` independently of hidden-member access. Stable local
  user/chat IDs preserve server order and unresolved fallbacks; one queued resolver batches same-ID reconfiguration through a serialized
  diffable apply; Dynamic Type and VoiceOver include title, role and presence. Live `updateChatMember`/full-info changes debounce a fresh
  authoritative load while retaining the first visible ID and pixel offset. Later-page failures remain visible in a table footer with
  explicit Retry. Account changes cancel child work and atomically remove the complete navigation suffix at the owning Profile.
- Edit captures account/user/client/chat identity. Cached creator or administrator `canChangeInfo` controls visibility, while every chat
  submit calls `getChatMember` for that captured user immediately before `setChatTitle`/`setChatDescription`. Self edit uses
  `setName`/`setBio`. Only changed fields are sent in sequence; successful first operations update the retry baseline, and a second-operation
  failure reports partial success without optimistic canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-132517-34076-25539.log`; final focused audit has no remaining API/model,
  pagination, diffable or account-lifetime finding after the atomic suffix fix. PID `33583` exposes a separate 176×56.67 Members/Admins
  row on the real three-member basic group; Members resolves exact `<member>, Owner`, `<member>, Member · online`, `лева, Member`, while
  Administrators independently resolves `<member>, Owner`. Screenshots:
  `.build/ui-probe-evidence/profile-management-controls.png` and
  `.build/ui-probe-evidence/profile-administrators-controls.png`. Edit was correctly absent for this non-admin account; no Save or other
  server mutation was performed.
- Runtime blocker/deferred: a safely reachable self/owned test profile was not mutated, so Edit form writes and live permission revocation
  are source-reviewed/build-proved rather than server-proved. Member promotion/removal/admin-right editors remain a later management gap.

### Member and administrator tag editor slice

- **P1 flow:** current `PeerInfoData.swift`, `PeerInfoScreenOpenMember.swift`, `ChatParticipantRightsScreen.swift` and TelegramCore
  `Ranks.swift` rank editing, compared with pre-Liquid `ChannelAdminController.swift`, adapted as an independent UIKit + TDLibKit tag
  operation rather than an administrator-rights mutation.
- TDLib boundary: captured-client `getChat` plus parallel actor/target `getChatMember` reads before presentation and again immediately
  before one awaited `setChatMemberTag`. Basic groups and non-channel supergroups are accepted; inactive targets and channels fail closed.
  Self editing requires fresh `ChatPermissions.canEditTag`. Editing another user requires creator status or fresh
  `AdministratorRights.canManageTags`; another creator is protected, and a non-creator may edit an administrator only when
  `canBeEdited`. The target tag must still equal the captured baseline before the write, preventing a stale editor from overwriting a
  concurrent change.
- UIKit editor preserves the current tag verbatim, counts at most 16 Swift characters, rejects controls and graphic emoji, accepts empty
  to remove the tag, and keeps transport errors visible without optimistic canonical state. Successful writes explicitly schedule an
  authoritative member-list reload instead of relying on the bot-only `updateChatMember` delivery contract. Account/client changes cancel
  preparation or saving and disable stale controls.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-153759-82885-28094.log`; final focused delta review CLEAN. Runtime PID
  `83599` exposed all three real member rows as enabled buttons with disclosure chevrons and the `Shows member tag controls` hint. Tapping
  self `лева` performed the fresh authority reads and produced `Can't Edit Tag` / `You no longer have permission to edit this member's
  tag.`, then OK returned to Members. Screenshots:
  `.build/ui-probe-evidence/member-tag-smoke-members.png` and
  `.build/ui-probe-evidence/member-tag-smoke-permission-denied.png`. No text was edited, Save was never pressed and no Telegram mutation
  occurred; Simulator remains booted.
- Runtime blocker/deferred: this live account cannot edit a tag, so an authorized Save/remove and post-success refetch are not exercised
  against the server. Promotion, demotion, removal and administrator-right editors are queued after the revalidation gate.

### Fullscreen gallery Open in Chat slice

- **P1 flow:** Telegram current/pre-Liquid gallery context action `Open in Chat`, adapted to the existing UIKit footer and BetterTG
  timeline-window loader without Telegram gallery/navigation infrastructure.
- Implemented: a plain 52×50 ellipsis control alongside unchanged Close/Share on the full-width classic blur footer. The action exists
  only when the presenting route supplies a captured account/client/source location and completion. Tap freezes a Sendable
  chat/message/topic identity, disables the control with progress and calls `getMessage` through the captured client. Completion checks
  action generation, selected ID, account/client, returned identity and exact topic for scoped profiles; base-chat routes intentionally
  accept any forum topic. A permanent delete, page change or account invalidation cancels quietly. Success forces a fade instead of the
  reverse tile transition and retains a separate navigation generation through dismissal; the completion rechecks account/client/context
  before invoking Profile or Chat. Profile pops only after modal dismissal; Chat uses its existing `prepareMessageWindow` path when the
  target is outside the loaded timeline. Secret-chat navigation needs no send/delete/save permission and remains allowed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-134050-43746-25199.log`; final focused delta review CLEAN. PID `44134`
  exposed exact footer frames `Close 4×790 52×50`, `More actions 294×790 52×50`, `Share 346×790 52×50` and the sole UIKit menu action
  `Open in Chat`. Selecting the first profile item (`1 of 1688`) completed gallery fade and profile removal, returning to
  the source group chat with the exact `Photo, 13:31` bubble visible. Evidence:
  `.build/ui-probe-evidence/gallery-open-in-chat-menu.png` and
  `.build/ui-probe-evidence/gallery-open-in-chat-result.png`; no Telegram mutation occurred.
- Runtime blocker/deferred: the safe smoke did not switch accounts or delete the selected message during the subsecond dismissal window;
  both races are generation-fenced and source-reviewed. Forward and Delete were subsequently recorded in their own slices below.

### Gallery Save and secured Share slice

- **P1/P0 flow:** Telegram current/pre-Liquid gallery media export and camera-roll save, adapted to UIKit, TDLibKit and Photos without
  Telegram media-box/resource infrastructure.
- Implemented: Save and Share serialize with Open in Chat and freeze the exact selected identity. Both perform parallel captured-client
  `getMessage`/`getMessageProperties`, require `canBeSaved`, reject both protected-content flags, paid media, self-destruct state and
  secret one-time photo/video/animation, then resolve the original largest photo or primary video/animation/sticker `File`. A user action
  requests full `downloadFile(limit:0,offset:0,synchronous:true)` and validates exact completion/path; cancellation only drops local
  authority and never calls global `cancelDownloadFile`. Selection/content/delete/account changes cancel before external commit.
- Photos uses `.addOnly`, re-fetches message/properties immediately before `performChanges`, sets `shouldMoveFile = false`, preserves
  creation date and a separator/control-stripped filename, validates images by ImageIO signature and Apple video by MIME plus playable
  AVAsset video track. GIF uses `.photo`, MP4 animation `.video`; WEBP sticker Save exports deterministic decoder frame 0 as PNG.
  TGS/WEBM sticker Save remains honestly hidden. Live Photo is labeled `Save Still Photo`, and Share requires an explicit
  `Share Still Photo` confirmation rather than silently implying paired motion. Photos commit is correctly treated as non-cancellable
  once submitted.
- Share now uses the same fresh protection gates instead of leaking an already-local protected path. It derives a canonical extension
  from fixed sticker format, TDLib MIME, ImageIO signature or MIME UTType; server filename contributes only a sanitized stem. A UUID temp
  hardlink (copy fallback) survives TDLib eviction/message deletion and is retained through `UIActivityViewController` completion before
  idempotent cleanup.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-140818-50364-12175.log`; final focused Telegram/TDLib/Photos delta
  review CLEAN. PID `50749` opened the real first profile photo through the secured Share preflight and displayed the system sheet with
  managed `bettertg-photo-<message-id>` / `JPEG Image · 6 KB`; the sheet was dismissed without choosing an external destination.
  PID `49849` exposed `Save Photo` and `Open in Chat` as the two More actions. Evidence:
  `.build/ui-probe-evidence/gallery-save-export-menu.png` and
  `.build/ui-probe-evidence/gallery-secured-share-sheet.png`.
- Runtime blocker/deferred: Save was deliberately not selected because it writes to the user's Photos library and no separate destructive
  smoke authorization was given. No reachable GIF/MP4 animation, WEBP sticker or Live Photo was exercised; those format branches are
  source-reviewed/build-proved. Delete is implemented below.

### Gallery Forward slice

- **P1 flow:** Telegram current/pre-Liquid gallery `MessageGroup` sharing, adapted to BetterTG's existing UIKit
  `ForwardMessagesViewController`, forum topic picker, comment state and `MessageForwardingService` rather than a parallel delivery path.
- Implemented: Forward is serialized with Open/Save/Share and captures account/client/chat/topic/selected ID before any await. A fresh
  `getMessage` validates the source. Non-album media proceeds as one message. For an album, no loaded gallery row is trusted: exact
  base/forum/direct-messages/Saved/thread history APIs request expanding 20/40/100 windows around the selected ID. A group is accepted
  only when both adjacent nonmatching boundaries are present or Telegram's 10-item cap is reached. History transport failures advance to
  the next window and finally degrade to selected-only; cancellation propagates immediately. Fresh IDs retain exact topic and server
  order semantics through `MessageForwardRequest`.
- Complete groups show an explicit `This Item` versus `All N Items` action sheet, so a protected/unavailable sibling never prevents the
  user from trying the selected item. The chosen request enters the production destination search, secret-chat forced-copy rules, forum
  topic drill-down, formatted comment, sender/caption options, partial-delivery handling and exact account fences. Gallery playback pauses
  only while the full-screen picker is visible and resumes on Cancel; successful delivery reports recipient count in the existing footer.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-142756-56092-20725.log`; final Telegram/TDLib delta review CLEAN.
  PID `54892` exposed the real `Forward to` picker with search, destination eligibility, Add a comment, `1 message` and disabled Forward
  before selection; Cancel returned to the exact `1 of 1688` gallery with Close/More/Share intact. Final build PID `57324` launched on the
  still-booted Simulator. Evidence: `.build/ui-probe-evidence/gallery-forward-picker.png`; no destination was selected and no
  `forwardMessages` mutation occurred.
- Runtime blocker/deferred: the reachable selected photo has no album, so the item/all choice and every topic-history variant are
  source-reviewed/build-proved rather than live-data-proved. Deliberate delivery remains a test-account mutation gap.

### Gallery Delete slice

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

### Forum notification quick-reply slice

- **P0 flow:** topic-aware notification reply using TDLib `getMessage`, `getForumTopic`, `sendMessage(topicId:)` and `viewMessages`.
- Implemented: exact account requirement; captured-client guards; authoritative message/topic fetch; closed/manage-topic and existing
  chat/payment checks; verified same-topic reply target; exact returned chat/topic assertion; fail-closed lookup behavior.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-080453-55869-29388.log` plus focused source delta-review.
- Deferred: deliberate test-account notification action proof and all-messages history/composer parity.

### Forum-aware Forward destination slice

- **P0 flow:** pre-Liquid/current forum drill-down behavior from `ChatControllerForwardMessages` and `PeerSelectionController`, adapted
  to UIKit + TDLibKit rather than Telegram controllers/state stores.
- Implemented: source route proof at prepare+delivery; destination chat/topic identity; multi-chat/multi-topic selection; exact cursor
  topic picker/search; closed/manage-topic and per-content eligibility; fail-closed forum discovery; exact forward result validation;
  partial retention; account fences; classic full-width material navigation/search and local selection summaries.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-075614-53821-9609.log`; local selection flow and classic header evidence
  `.build/ui-probe-evidence/forum-forward-topic-plain-final-*`; no Forward/send mutation, PID 54141 alive, Simulator booted.
- Deferred: comment/forward-draft transition, deliberate test-account delivery and all-messages headers.

### All-messages forum timeline foundation slice

- **P0/P1 flow:** base forum adjacent-topic runs and jump-free history extension from pre-Liquid/current
  `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift`, adapted to one inverted UIKit collection without Telegram
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: stable `message(id)` / `album(mediaAlbumId)` / `topicHeader(topicID,runStartMessageID)` identities; complete
  projection rebuild for `A,A,B,B,A`; official 34pt centered 22pt topic control with 16pt General/custom/generated icon, one-line title
  and chevron; lazy account/client-fenced `getForumTopic` cache plus `updateForumTopicInfo`; authoritative topic tap; message-only
  read/prefetch/playback/context/selection paths; raw TDLib pagination cursor; cross-page album coalescing; permanent member-delete
  survival; message-window reuse; and visible message + pixel-offset restoration across boundary-header insert/remove/merge.
- Production routing follows live `Chat.viewAsTopics`. Base text/photo/edit/draft and chat-action contexts resolve to discovered General
  or the replied message's exact topic; closed-topic replies fail closed, reply transitions cancel the prior topic action, and the base
  draft key remains `topic:nil`. Voice/video manifests now carry a separate immutable send topic through record/pause/resume/preview,
  relaunch, enqueue, resend and exact record/upload/cancel actions; a newer composer reply is never cleared by an older media draft.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-085723-71772-1312.log`; wrapper/idb launch PID `67526` stayed
  alive and ordinary chats retained full composer controls. `.build/ui-probe-evidence/forum-all-messages-*` records the hierarchy scan;
  no safe `viewAsTopics == false` forum exists in current simulator data, so live header tap remains a data-state blocker. Fresh PID
  `71701` passed `.build/ui-probe-evidence/forum-all-messages-media-destination-*`: voice Ogg/Opus + base-draft/frozen-topic relaunch,
  video send outcome/legacy/thumbnail/tombstone cleanup, and ordered multi-segment video recording trim/thumbnails/frozen-topic handoff.
- Deferred: live all-messages topic-header/pagination/album seam proof on an account with a reachable forum in this mode.

### Keyboard and self-sizing timeline anchor slice

- **P1 flow:** Telegram-style `messageId + pixelOffset` retention across viewport/intrinsic-size changes in the inverted UIKit history.
- Implemented: message-cell pre-fit height notification; one coalesced visible-message anchor for autonomous self-sizing; exact anchor/latest
  restoration around single/bulk diffable reconfigure, composer/search/selection/keyboard insets, Dynamic Type and rotation; mutation-depth
  ownership so stale deferred size callbacks cannot overwrite a newer snapshot/inset/rotation anchor; active pan/deceleration remains untouched.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-091301-75604-22504.log`; focused delta-review clean. PID `75942`
  retained `Video message, 0:13` at `{{53,381},{260,260}}` and `chat-date-1787342400` at `{{172,348},{58,22}}` across two
  hierarchy-derived focus attempts (`Δx/y/w/h=0`). Simulator did not present `AXKeyboard`—likely hardware-keyboard state—so the
  non-no-op keyboard-attached transition remains a runtime proof blocker. Evidence: `.build/ui-probe-evidence/timeline-anchor-fresh-*`.

### Delete collapse/fade/slide slice

- **P0 flow:** Telegram-style restrained delete transition without dust/particles, integrated with authoritative TDLib
  `updateDeleteMessages` and the inverted diffable timeline.
- Implemented: ChatVM announces only bubbles whose complete source-message set disappears; visible sources become noninteractive and
  animate 140ms opacity + directional 24pt slide + 0.98 scale; the delayed heterogeneous snapshot then performs layout collapse. Rapid
  deletes coalesce to one deadline, cell reuse resets all presentation state, nonvisible deletes apply immediately, album-member survivors
  stay in place, video teardown still follows `didEndDisplaying`, and the collapse anchor is restricted to IDs surviving in canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-092113-77487-3754.log`; focused source/delta review clean. No deliberate
  server delete was performed, so visual runtime mutation proof remains deferred.

### Composer send-flight slice

- **P0 flow:** pre-Liquid Telegram composer source-to-message insertion transition, adapted to real UIKit snapshots and TDLib temporary
  IDs without Telegram transition infrastructure.
- Implemented: synchronous capture of visible reply, formatted text, selected-photo strip, caption, active voice/video preview and
  retry-button sources; one serialized composer text/media send; temporary→success/failure ID aliases before or after acceptance;
  canonical album/message target lookup; 320ms staggered frame/corner/opacity flight into the real visible bubble; bounded offscreen
  fallback; five-second/deinit/account cleanup. Voice direct/trim-preview/promotion/retry and video recorder/retry paths bind runtime-only
  transition tokens to their durable draft IDs, accept exact returned message IDs, and cancel retained/interrupted/discarded failures.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-093342-80738-1901.log`; focused source/delta review clean. No deliberate
  test-account send was performed, so the visible flight remains a mutation-gated runtime proof gap.

### UIKit file/document attachment slice

- **P0 flow:** pre-Liquid/current attachment-menu document flow, adapted to `UIDocumentPickerViewController` and TDLib
  `InputMessageDocument` / `sendMessageAlbum` with the existing immutable forum send context.
- Implemented: Files menu and cancellable multi-selection; security-scoped provider copies capped at 10; account/location rejection of
  stale picker completion; mutually exclusive photo/document strips; filename/size/remove accessibility; Dynamic Type row growth; exact
  document permission and General/reply topic; first-item caption; homogeneous 1–10 document album; partial-result retention of only
  unsent selections; duplicate-send serialization and composer→bubble flight. Temp ownership uses provisional persisted leases before
  any upload await, binds outcome-before-registration aliases to TDLib IDs, protects active files from remove/replace/deinit/scavenging,
  migrates failed IDs, and releases on global success/permanent delete even after ChatView closes. Lease paths require a generated UUID
  prefix and exact managed parent; unleased orphans expire after 24h and abandoned leases have a 30-day recovery ceiling.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-095820-86651-17797.log`; focused source/delta review clean.
  PID `82584` proved enabled Attach Files at `{{10,697},{250,42}}`, UIKit Recents/Search/Browse, exact Cancel AX hit and unchanged
  composer after cancellation. Evidence: `.build/ui-probe-evidence/document-attachment-*`; no file was selected or sent.

### UIKit emoji/sticker/GIF composer slice

- **P0 flow:** pre-Liquid/current emoji/sticker/GIF input panel behavior, adapted to a UIKit page sheet and TDLib-native
  `getStickers`, `getSavedAnimations`, `InputMessageSticker` and `InputMessageAnimation`.
- Implemented: Emoji/Stickers/GIF segmented grid; debounced search and mode-generation cancellation; account/client/chat fencing before
  loads and selection; installed regular sticker query with every Premium sticker excluded; saved-GIF filtering; exact picker-cell AX;
  TGS/WebP/WebM reuse with offscreen pause and GIF thumbnail cancel/restart; repeated emoji insertion with debounced route draft; exact
  other-message permission, General/reply topic and returned-destination assertion. Sticker sends preserve typed text while clearing the
  accepted reply through the captured draft topic with generation-fenced retry; GIF caption clears safely; both use serialized sends and
  the insertion-flight protocol. No Premium/Stars/custom-emoji results are offered.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102014-91617-3187.log`; focused source/delta review clean. Runtime
  PID `90585` proved the UIKit sheet, exact three segments, 64 enabled emoji buttons, 16 non-Premium sticker buttons, 16 saved-GIF
  buttons, offscreen-safe navigation and Done return. Evidence: `.build/ui-probe-evidence/composer-media-picker-final-*`; no
  emoji/sticker/GIF was selected or sent.

### Forward comment/draft slice

- **P0 flow:** pre-Liquid/current forward destination comment state, adapted to the existing UIKit multi-recipient/topic picker and
  TDLib `sendMessage(InputMessageText)` followed by `forwardMessages`.
- Implemented: expanding formatted Add a comment field retained across topic drill-down/search/retry; keyboard-layout-guide attachment
  with interactive dismissal and safe-area toolbar switching; Dynamic Type height refresh; comment snapshot at delivery start; exact
  basic-message/private/paid/forum/closed/admin eligibility; account/client checks immediately before mutation; exact returned topic.
  Each destination records the delivered `FormattedText`, so a failed forward retries without duplicating an unchanged successful
  comment, while an edited comment is a new intent. Comment failure blocks that destination's forward; ambiguous/partial forwarding keeps
  the existing nonretry policy, and controls re-enable with the comment intact.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102642-93175-2531.log`; focused source/delta review clean. PID `93577`
  reached the real message context menu, but idb omitted its Forward overlay action, so safe navigation to the comment field was blocked.
  Evidence: `.build/ui-probe-evidence/forward-comment-final-*`; no comment or forward mutation occurred.

### Date and topic boundary slice

- **P1 flow:** pre-Liquid/current `ChatMessageItemImpl.swift` date/topic merge break and `ChatMessageDateHeader.swift` 34pt service
  header ordering, adapted to stable heterogeneous UIKit diffable items.
- Implemented: calendar-start stable IDs; 34pt inverted rows with centered 22pt localized pills; Today/Yesterday/year-aware labels and
  header accessibility; one separator per day in ordinary and forum histories; exact visual date→topic→message ordering on simultaneous
  boundaries; no duplicate topic header at midnight; message-only read/prefetch/selection/playback; structural pixel-anchor reuse; and
  significant-time/locale snapshot reconfiguration so cached Today labels and timezone-derived identities cannot go stale.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-090344-73347-22038.log`; runtime hierarchy/screenshot evidence is
  `.build/ui-probe-evidence/date-headers-*`. Fresh PID `73694` exposes `chat-date-1787860800` (`Aug 28`, 58.67×22) and
  `chat-date-1788033600` (`Yesterday`, 76.67×22); 6pt row insets plus existing 5pt message gaps prove the exact 34pt row with zero
  overlap, while the enabled composer remains at y=796.67.

### Writable explicit forum topic slice

- **P0 flow:** pre-Liquid/current closed-topic input panel, topic placeholder, text/attachment/media recording, activity and draft
  semantics from `ChatInterfaceStateInputPanels`, `ChatTextInputPanelNode`, `ChatController`, `ChatControllerOpenAttachmentMenu` and
  `ChatControllerMediaRecording`, adapted to UIKit + Combine + TDLibKit without Telegram infrastructure.
- Implemented: immutable send context; exact topic for text/photo/album/voice/video/action/draft; returned-topic assertions; same-topic
  replies; content-specific and live closed-topic authority; dirty/stale draft fences; generation-safe clear retries; edit preservation;
  partial-album retention; exact-location reactions/polls/delete/forward source; writable/restricted UIKit composer states and topic
  placeholder. Base forum history is now handled by the separate all-messages resolver above.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-073123-48367-634.log`; non-mutating real-topic route and production
  composer evidence `.build/ui-probe-evidence/forum-topic-write-final-*`; PID 48686 alive, Simulator booted.
- Deferred: forward comment, all-messages General-or-reply resolver/run
  headers, deliberate test-account send/draft mutation, topic-scoped pinned banner and remaining attachment types.

### Topic media draft identity slice

- **P0 flow:** thread-scoped composer media ownership from pre-Liquid/current `ChatInterfaceState` and
  `ChatControllerMediaRecording`, adapted to Codable actors + TDLibKit rather than Postbox/SignalKit.
- Implemented: stable account/chat/full-topic key; four version-tolerant manifests; durable one-time legacy policy; exact restore,
  deduplication, enqueue, discard, recording handoff and resolution routing; draft-UUID outcome names; voice registration barrier;
  account/topic coordinator snapshots; stale account restore/promote guards; recorder receives the immutable destination.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-065904-41355-13754.log`; terminal probe files and run metadata
  `.build/ui-probe-evidence/topic-draft-key-*`; PID 41675 alive after proof, Simulator booted.
- Deferred: resolved network send context, topic text drafts/dirty generations, closed-topic write permission, exact returned-topic
  assertions, then attachments/voice/video UI enablement and topic-aware Forward/all-messages headers.

### Classic chat list row slice

- **P2/P1 flow:** pre-Liquid `ChatListItem` presentation applied to existing UIKit chat/folder data and actions.
- Implemented: full-width 76pt rows; 60pt avatar at x=10; content/separator x=80; pinned/normal/highlight backgrounds; title/preview/date;
  pending/failed/delivered/read state; unread/muted/marked-unread/pin accessories; capped Dynamic Type; full-state VoiceOver; full-row context
  extraction and tap target. Existing diffable stable IDs, prefetch, search, gestures and TDLib actions remain unchanged.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-063859-35683-18833.log`; exact frame/tap evidence
  `.build/ui-probe-evidence/classic-chat-rows-*`; first tap opens Saved Messages; PID 35152 alive; Simulator booted.
- Deferred: typing/action preview, verified/scam/status/story adornments, archive reveal gestures and full account fencing for list mutations.

### Classic shell blur slice

- **P2 flow:** full-width folder/tab chrome and context-menu material, based on pre-Liquid `ChatListFilterTabContainerNode` selection
  geometry and classic UIKit material rather than Liquid Glass.
- Implemented: edge-to-edge bottom blur including safe area; rectangular scroll viewport; exact three-point segment line; selected accent
  text; ordinary system-material context menu; classic 16/10pt menu/highlight corners; all Glass-only APIs and marker strings removed.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-062914-33482-14249.log`; real account hierarchy/screenshot and long-press
  menu evidence `.build/ui-probe-evidence/classic-shell-*`; PID 33820 alive; Simulator booted.
- Deferred: remaining navigation/search/action surfaces still need a complete full-width/no-floating audit.

### Forum topic browsing slice

- **P0 flow:** pre-Liquid/current `ChatListNodeLocation`, `ChatListNodeEntries`, `ChatListItem`, `ChatControllerContentData` and
  `ChatControllerLoadDisplayNode`, adapted to UIKit + Combine + TDLibKit without Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: account/client/chat/topic route identity; captured-client ref-counted open lease; exact topic cursors/order/hidden/search;
  update refetch and transient retention; explicit topic history/search/read acknowledgement; target-message topic resolution; classic
  UIKit rows with General/custom-emoji icons, pin/closed/draft/unread variants, Dynamic Type, VoiceOver and offscreen animation pause;
  stable-ID reconfiguration; fail-closed push/forward; VM-level read-only barriers with non-mutating content access preserved.
- Proof: warning-free build log `.build/logs/xcodebuild/build-Debug-20260831-062650-32938-29366.log`; device hierarchy/screenshot files
  `.build/ui-probe-evidence/forum-topics-*`; `[1,42,77]`, hidden 99 absent, AX tap `(201,262)`, status
  `Opened topic 42 · Read-only`, PID 31980 alive.
- Deferred: all-messages topic-run headers, topic composer/writes/durable drafts, topic forwarding selection, topic actions/mutations,
  General hidden toggle/admin controls, unread navigation and live server pagination/mutation smoke.

### Pinned message slice

- **P0 flow:** pre-Liquid/current `ChatInterfaceStateContextMenus`, `ChatControllerLoadDisplayNode`,
  `ChatPinnedMessageTitlePanelNode` and `ChatControllerNavigateToMessage`, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: exact Saved/private/group/channel pin modes; fresh `canBePinned` preflight; one serialized chat mutation; optimistic
  newest-pin state with authoritative revision rollback fences; account/client/generation guards before and after TDLib; initial and
  refreshed `getChatPinnedMessage`; 404-only clearing; cache/permanent-delete/edit/content/isPinned reconciliation; direct-message/forum/
  topic/album/service/sending gates; shared spoiler-safe thumbnail extraction; 50pt full-width blur banner; separate Open/Hide AX controls;
  local hidden-ID token; newer-pin resurfacing; selection/search suppression; stale-animation rejection; inverted-history inset stability.
- Proof: `Pinned message probe: modes=true, visibility=true, 404-only-clear=true, newest-only=true, banner-height=50, local-hide=true, navigation=true, uikit=true, swiftui=false`.
- Deferred: nearest-visible pin rotation, pinned-only list/pagination, admin unpin undo, older-pin warning details, topic-scoped pins and
  deliberate live server mutation proof.

### Message reactions slice

- **P0 flow:** pre-Liquid/current `ReactionButtonListComponent`, `ChatMessageReactionsFooterContentNode`,
  `ChatMessageBubbleItemNode` and `ChatController` toggle/restriction behavior, adapted without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: representative-bubble standard/custom reaction rendering; Telegram count-minus-own-selection sorting; exact 30/20pt
  geometry and 6pt wrapping; chosen/unread styling; reusable accessibility; account-keyed custom-emoji sticker cache; offscreen
  animation pause; zero-state context picker; authoritative per-message availability; Premium/paid exclusion; maximum-count-safe
  optimistic add/remove with rollback; chosen removal under restrictions; normal-client interaction/unread reconciliation; live
  chat permission/max updates; account-switch fences; chat/topic reaction-read acknowledgement; read-only topic and ephemeral mutation gating.
- Proof: `Message reaction probe: reducer=true, remove=true, add=true, max-count=true, unread=true, paid-excluded=true, wrapping-chips=true, uikit=true, swiftui=false`.
  Device hierarchy proves the exact two-row frames/gaps and paid omission. Fresh center taps produce
  `👍: 2, Not selected` and `❤️: 1201, Selected` while PID 11956 remains running.
- Deferred: custom-emoji origination grid, reactor list/avatars, removal animation, forum-topic identity and live server mutation proof.

### Forward and message-selection slice

- **P0 flow:** pre-Liquid/current `ChatMessageSelectionNode`, `ChatMessageSelectionInputPanelNode`,
  `ChatControllerForwardMessages` and `PeerSelectionController` behavior, adapted to UIKit + Combine + TDLibKit without
  Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: context Select/Forward gates; whole-album direct forwarding; stable selection/reuse/accessibility; classic geometry and
  transition timing; 100-child limit; exact per-child property/content preflight; multi-delete; Saved/main/archive/offline/server
  destination discovery; raw-chat secret/private/group/channel eligibility; multi-recipient progress; sender/caption modes; safe
  nonretryable treatment for unknown partial subsets; account-switch fences before every mutation.
- Proof: `Message forwarding probe: normalized=true, limit=true, options=true, album-atomic=true, multi-recipient=true, account-scoped=true, uikit=true, swiftui=false`.
  Device hierarchy proves `forward-probe-saved-messages` and `forward-probe-design-group` are full-width 402×62 AX controls;
  center taps select both, enable the 66×56 Forward control and produce `Ready: 3 sorted IDs · 2 chats` without a Telegram send.

### Reply, quote and forward provenance slice

- **P0 flow:** pre-Liquid/current `ChatMessageReplyInfoNode`, `ChatMessageForwardInfoNode` and bubble tap semantics, adapted without
  AsyncDisplayKit/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: cross-chat/ID-zero/story/unavailable fallbacks; forwarded target author override; `ForwardSource` chat-first display and
  message→chat→sender navigation; hidden-author static state; thumbnails including round video notes; 1-line ordinary and 5/50-line manual
  quote layout; source/context accessibility and bubble custom actions; exact quote range search/highlight; external reply input and every
  media draft restoration path; account/client guards; cache/permanent-delete and stale-generation fences.
- Proof: `Message metadata probe: inline=true, unknown-chat=true, source-priority=true, expand-then-navigate=true, forward-navigate=true, external-input=true, utf16-quote=true, highlight=true, uikit=true, swiftui=false`.
  Screenshots are `.build/message-metadata-final-*.png`; Simulator remains booted.

### Exhaustive MessageContent breadth slice

- **P0 flow:** classic content routing based on the pre-Liquid contact/map/poll/action/animated-sticker nodes and
  `ServiceMessageStrings`, adapted to UIKit + Combine + TDLibKit rather than Texture/SignalKit/Postbox/Display/ComponentFlow.
- Implemented: 104-case catalog; shared summary/caption extraction; audio and document rows plus attachment albums; explicit primary-file
  download/cancel/reconcile and thumbnail-only prefetch; details-first contact card with five vCard lines; actual MapKit snapshots and
  absolute live-location timer; single/multi poll submission, persisted pending state, authoritative result/quiz colors and VoiceOver;
  visibility-gated animated emoji/rolling regular dice with safe resolved fallback; centered service pills; italic unsupported placeholder;
  explicit excluded-product fallbacks; account-captured, generation-safe prefetch.
- Proof: the DEBUG probe instantiates production views with real TDLib model values rather than parallel mock views. Its Documents proof is
  `MessageContent probe: tdlib=1.8.66-022d6020, exhaustive-cases=104, views=file,file,attachmentAlbum,contact,location,location,poll,poll,stickerGlyph,stickerGlyph,service,service, sized=true, poll-actions=poll:0,poll:0,1, action-proof=true, uikit=true, swiftui=false`.
  Device screenshots are under `.build/message-content-final-postbuild-*.png`; Simulator remains booted.

### FFmpeg range controller slice

- **P0 flow:** non-Apple WebM VOD controller, following pre-Liquid/current `ChunkMediaPlayerV2.swift` buffering/seek/EOF and
  `ChunkMediaPlayerDirectFetchSourceImpl.swift` packet-lookahead behavior through TDLib `downloadFile(offset:limit:)`,
  `getFileDownloadedPrefixSize`, `updateFile` and `cancelDownloadFile`.
- Implemented: MainActor Combine controller; serialized 2s normalized packet horizon followed by a bounded 60s
  decoder job; exact 1s source gate plus Apple raw sufficiency; play/pause/rate/seek/EOF; non-zero-origin and per-track intervals;
  typed offline/retry failures; last-target-wins generations; offscreen renderer/range suspension; sparse audio degrades to silence;
  source demand cancellation is operation-token/last-demand scoped.
- Verification: `./build.sh` and `./test.sh` pass with Xcode 26.6. The 11.208s DEBUG fixture launched through
  `RUN_ARGUMENTS="-media-probe-vod-ffmpeg-controller" ./run.sh` and reported deferred load, ≥1s initial gate, ≤60s window,
  autoplay, visible buffering, stable pause, 1.5× rate, offscreen suspension/cancellation, preserved intent, last-seek-wins,
  seek-first PTS, EOF/no-loop, offline/retry, seek clamp, zero renderer errors, finite range downloads, zero full downloads and cleanup.
  `git diff --check` is clean.
- Subsequent slices below record persistent session rollover and the sample-buffer PiP implementation. Active system PiP/background
  restore remains a physical-device proof gap, subject to the new revalidation gate.

### Production FFmpeg gallery routing slice

- **P0 flow:** WebM/VP9 VOD in the existing UIKit inline/fullscreen owner, following pre-Liquid `UniversalVideoGalleryItem.swift`
  central visibility and `ChunkMediaPlayerV2.swift` backend continuity without importing Telegram infrastructure.
- Implemented: MIME+extension routing; public range streaming; secret/non-streaming full-download handoff; cached-file FFmpeg re-entry;
  one controller/view/lease across inline and fullscreen; mute/rate/seek/control routing; offscreen demand suspension with preserved intent;
  first-frame/thumbnail transition fallback; typed failures; generation guards for every native and FFmpeg Combine stream; stale lease
  invalidation; native MP4/MOV/M4V and AVPlayer PiP isolation.
- Verification: `./build.sh build` succeeds without warnings. The combined native+FFmpeg owner probe launched through
  `./build.sh run -- -media-probe-gallery-owner`; idb readback proves `ffmpeg-route=true`, `same-controller=true`,
  `offscreen-intent=true`, `finite-ranges=true`, `ffmpeg-invalidate=true`, native `same-item=true`, zero full downloads for streamable
  fixtures, exact return-to-inline continuity, terminal lease cancellation and no stale attachment callbacks.

### Persistent FFmpeg session slice

- **P0 flow:** retain demux/decoder/SWR state across VOD high-water expansions, matching pre-Liquid `ChunkMediaPlayerV2.swift`,
  `FFMpegMediaDataReaderV2` and `FFMpegFileReader` session-per-seek behavior through TDLib finite range reads.
- Implemented: separate exact one-shot and soft streaming APIs; one open per seek-generation; authoritative Continue horizon; full crossing
  frames; per-track emitted cursors; end-aware track completion; globally sequenced interleaved compressed-packet FIFO with hard count and
  payload/side-data/overhead footprint bounds; cumulative session metrics and per-pump safety budgets; persistent callbacks/context;
  terminal cancellation and close barrier; no repeated lookahead after session start.
- Verification: SHA-pinned two-second boundary fixture proves three uneven pumps, one open, no rollover seek, monotonic A/V, no added
  previous-end→next-start discontinuity, exact seek, persistent supersession/cancel and EOF/SWR tail. SHA-pinned sparse unequal-track
  fixture proves video 12s plus audio packets at 0…2 and 8…10s, non-EOF first horizon, full terminal audio/video, and ordered FIFO use
  (`25` packets / `24,113` bytes). The production controller proves eleven 1s DEBUG pumps on one session plus all prior playback states.

### Sample-buffer Picture in Picture slice

- **P0 flow:** FFmpeg WebM VOD PiP using the pre-Liquid/current `NativePictureInPictureContentImpl` AVKit contract while retaining
  BetterTG's existing UIKit owner, Combine state, TDLib range session and restore coordinator.
- Implemented: exact layer-keyed `ContentSource`; strongly retained lock-backed playback adapter; finite current-containing range;
  playing/buffering/paused mapping; explicit setPlaying; signed skip with past-end reset; render-size forwarding; background audio allowed;
  pause/duration invalidation; native/sample source reconciliation; start/stop timeouts; pending-start strong retention; deletion/restore/audio
  lifecycle; deferred failed-player teardown; forced-timeout controller retirement and exact stale-controller rejection.
- Verification: the production gallery-owner fixture exercises the real content-source factory despite system PiP being unsupported and
  proves sample layer/delegate identity, transport/range behavior, exact-once completion, source continuity, zero extra TDLib cancellation,
  deferred stop-before-close, native fallback route, pending-start barrier and stale timeout callback rejection. Actual system-window PiP
  and background restore still require a capable physical device.
