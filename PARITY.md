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
Editing these documents does not start or resume a goal. The user explicitly resumed continuous work after the `8268947`
handoff; the goal is active. The earlier pause no longer applies. This does not mean Telegram parity is complete.
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
| P0 | MediaCore and animated media | No VLC dependency/consumer; production TGS/WebP/WebM-alpha and custom/animated emoji routes; decode ownership, alpha/timing/sync, bounded caches, offscreen pause, prefetch/cancel/fallback | needs-fix — first source pass; A05/A06/A07 bounded repairs/probes; A08/A09 remain; authenticated animation smoke pending |
| P0 | Voice and video notes | Ogg Opus/waveform and H.264/AAC output; hold/cancel/lock, pause/resume, preview/seek/trim, cameras/limits; durable draft/send/retry ownership, interruptions, relaunch and terminal cleanup | reviewed with bounded A11–A17/A26 repairs, including own-draft relocation/reinstall/discard and native lifecycle/finish/handoff probes; actual OS suspension, audio delivery, hardware and server proof remain open |
| P0 | VOD, FFmpeg and PiP | Playback before full download, finite offset/limit reads, prefix/EOF checks, seek/refetch, lookahead, cancellation leases, buffering/offline/retry; same owner/playhead across inline/fullscreen/PiP, A/V sync and bounded memory | needs-fix — range/decoder/renderer source pass A01–A04; owner/PiP account-boundary pass at `909215a` finds A18/A19; full lifecycle/device proof incomplete |
| P0 | Message content and actions | Current generated MessageContent cases mapped to real rendering/actions and safe fallback; entities/web/captions/spoilers, albums, polls/quiz/dice/service; reply/quote/forward/edit/delete/select/reactions/pins/topics/unread/delivery | needs-fix — classification/media dispatch source pass at `176eab9`, structured actions at `cf885b1`; A10/A20/A21 concealment and A31 poll lifetime; live content/action matrix unverified |
| P0 | Composer and timeline | Complete island states and production sends; temporary/final IDs and snapshot transitions; stable IDs, raw pagination, messageId+pixelOffset under prepend/edit/resize/keyboard; cancel/retry, prefetch, off-main work | needs-fix — timeline A22; composer/edit/forward/transition source pass at `bb01b8f` finds A24/A25; live pagination/keyboard/flight proof pending |
| P0/P1 | Cross-flow account and authority boundaries | Captured client/account/chat/topic; stale callbacks, Combine/task teardown, updates, storage/cache keys, permission revalidation; pending sends/deletes/account switches; shared player/file/audio ownership | needs-fix — A05/A06/A12/A13/A14/A18/A19 bounded repairs; remaining subscribers A23 and secondary-route A30 remain; cross-flow runtime proof incomplete |
| P1 | Profiles and galleries | Peer/self roles, avatar/history, member/admin/tag rights, shared-media pagination; selected item, transitions, zoom/paging/dismiss/control gestures, rotation, captions, export/forward/delete/open-in-chat | reviewed with bounded A27/A28 repairs — source pass at `d8ed16e`; effective info-edit policy and pagination request identity probed; hardware/server/gesture proof incomplete |
| P1/P2 | Accounts, chat lists/folders and classic shell | Inventory existing add/auth/switch/remove/logout paths and missing isolation; archive/search/edit/reorder/include/exclude/pin/mute/read/delete/clear/drafts; safe-area full-width blur and prohibited production UI markers | needs-fix — event/RPC A23, mutation A29, foreground client replacement A30. Registry/auth/list/chrome initial source pass done; live multi-account/logout and full secondary-surface proof pending |

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
| Voice/video notes | `ChatBottomArea`, `VideoNoteRecorderViewController`, `ChatVM` → capture/writer/codec, recording/send stores and coordinators, message playback | Voice source pass at `37c8b44`: recording/trim/PCM/codec, preview, send/retry/relaunch/outcomes and destination ownership; A11–A14. Independent video source pass at `8268947` confirms shared A12/A13 plus A15–A17; camera/interruption/server behavior remains unproved |
| VOD | `ChatView`/`ChatViewAlbum` → `GalleryVideoPlaybackOwner`, `LocalMediaPlayer` or FFmpeg sample player → range coordinator/resource loader/decoder/renderer/C AVIO | Source pass over range/loader and C/Swift decoder/render session; primary owner/PiP account/restoration pass at `909215a` finds A18/A19; other lifecycle and active-system proof pending |
| Content/actions | `MessageContentPresentation`, `MessageMetadataPresentation`, structured/text/reaction views → `ChatVM`, `MessageForwardingService`, topic/forward controllers | Source pass at `176eab9`: pinned 104-case classifier, production cell/media dispatch and spoiler/secret guards; A10/A20/A21. Structured actions at `cf885b1` find A31; exhaustive live content/action behavior remains unverified |
| Composer/timeline | `ChatBottomArea`, `ChatView`, `ChatVM`, `ChatDraftKey`, `MessageSendTransition`, date/topic header models | Timeline source pass at `3b566dd`: raw cursor, album/header identity, anchors and prefetch; A22. Composer pass at `bb01b8f`: edit dispatch/completion, semantic formatting, snapshot lifetime, ID aliases and forward isolation; A24/A25 and transition proof gaps |
| Profiles/gallery | Peer profile/control/avatar controllers → `ChatViewAlbum` gallery and owner/export/actions | Source pass at `d8ed16e`: roles, member/admin/tag controls, edit, avatar history/video, pagination, transition identity/cleanup, gesture arbitration and rotation; A27/A28. A19 isolated context/owner probes pass; active system PiP and real server actions remain unverified |
| Accounts | `TDLib`, `TelegramAccountRegistry`, root/settings/login controllers → client activation/retirement, storage, update subjects | Initial source pass at `cf885b1`: UUID databases, atomic registry, client retirement, auth routing and background ownership; A23/A30. No real add/switch/logout or notification-service handoff proof |
| Lists/shell | `MainView`, `RootVM`, `FolderView`, `ChatFolderManagementViewController`, navigation/context-menu views | Initial source pass at `cf885b1`: frozen list payloads versus dynamic action clients A29, page/tab state and full-width safe-area constraints. Secondary surfaces/search mutations and visual matrix remain partial |

### Astra findings and repair queue

Active queue: A08 animated-video timing and A10 text spoilers, then A09 inline animation and A20 media concealment.
A30b2 now enables quiescent Chat foreground recovery with bounded real-chat smoke; A15b2 voice lifecycle has native isolated proof.
A30a root lists, A30b1 composer-transfer foundation and A16/A17 video ownership retain their bounded proofs below;
ForumTopics, Archive, already-open editors, active capture and full OS/server lifecycle coverage remain separate.
A26 relocation and A29 frozen list mutations have integrated bounded proofs below; A29 cold-launch folder navigation also passes.
A12/A13/A18 delivery correlation and accepted-update transport are repaired with bounded proofs below;
callbacks rejected before publication and recovery without a registered temporary ID remain separate gaps.
A11 preserves voice recording route/reply/caption, PCM, waveform, trim and revision contracts across lifecycle teardown;
its bounded proof and remaining runtime limits are recorded below. A14 and A19 now have integrated isolated proofs;
A14's real no-send promotion exposed A26 on reinstall; the follow-up repaired relocation and recovered that same own draft.

Locations A01–A10 refer to the reviewed `6b417da` implementation unless a fix is recorded; voice A11–A14 were reviewed at
`37c8b44`. Source findings are not runtime proof. A repaired finding does not mark its entire area fixed.

| ID | Priority | Evidence / trigger | State and bounded repair |
| --- | --- | --- | --- |
| A01 | P1 | `TDLibVODRangeSource.waitForSignal/timeoutWaiter`: canceled sleep still invokes timeout; a repeated wait reuses read ID and seek generation, allowing an old callback to consume its replacement | fixed in `37c8b44`: per-registration token, cancellation return; obsolete/current-deadline probe passed |
| A02 | P1 | `ensureAvailable` can receive `updateFile` while awaiting an older zero-prefix RPC result, then register after the only wakeup; bytes wait for timeout despite being cached | fixed in `37c8b44`: compare update sequence before registering at all three wait sites; suspended-prefix production-read regression passed |
| A03 | P1 | `FFmpegSampleBufferRenderer.pause` publishes on every call; player snapshot delivery calls `updatePlaybackGate`, which pauses again in paused/buffering/EOF states | fixed in `3005369`: deduplicate complete identical snapshots while preserving every pause transport command; settled feedback, seek/rate/EOF/offline/retry probes passed |
| A04 | P1 | Decoder/controller expose maximum A/V duration, but readiness always requires video; a 5s-video/60s-audio file accepts a 20s seek with no possible video frame and reaches watchdog failure | fixed by `83103ba`, `14a01c5`, `ef8f4ba` — explicit video-main end, estimated-versus-final duration authority and verified EOF/watchdog teardown; native and integrated decoder/controller probes pass, including under/overestimated metadata. Cold large-file partial-range proof remains separate |
| A05 | P1 | TGS/WebP/FFmpeg animation views use global `nc.updateFile` plus numeric file ID and deferred dynamic `td`; account switch precedes root teardown. Custom-emoji fetch also resolves a dynamic client | fixed bounded source/transport — `128ada2` freezes requests and scopes delivery/decode; `6e5b287` requires originating clients through every animated consumer and custom-emoji fetch, clears reused thumbnails. Isolated transport/native/PiP regressions pass; real multi-account sticker playback unverified. A06 has its separate shared-demand repair |
| A06 | P1 | Animation view teardown/prefetch calls global file cancellation without shared demand ownership; one reused copy can cancel another visible copy's pending download | fixed bounded animated demand — `09fa140` shares account/client/file leases across TGS/WebP/WebM views and animated prefetch; last-owner cancellation/reacquisition and queued terminal updates pass isolated production-pool probes. Static `.none` prefetch and VOD-range arbitration remain separate; actual TDLib/view scheduling is unverified |
| A07 | P1 | `FFmpegAnimatedVideoView.show` constructs its decoder on MainActor; initializer opens/probes FFmpeg input and codecs synchronously, even on asset-cache hits | fixed in `3917128`: native-free init, worker-isolated prepare/read/reset/deinit and setup/reuse fences; actual native-operation thread/lifecycle probe passed before and after integration |
| A08 | P1 | FFmpeg animation indexes use capped 30 FPS and at most 600 estimated frames while decoder returns every source frame; 60 FPS and long animations never reach real EOF, variable-duration GIF timing is lost | needs-fix: PTS/duration scheduling and decoder EOF, separately bounded cache |
| A09 | P1 | Apple-container `messageAnimation` routes to static `FileMediaPreviewView`; only fullscreen owns playback | needs-fix: account-scoped inline AVFoundation animation loop with visibility/reuse/cancel contracts |
| A10 | P1 | `Utils/Text.swift` spoiler formatting only adds background color; `MessageTextView.configure` retains visible text/custom emoji and exposes unredacted text through accessibility | needs-fix — primary source check confirmed; add hidden/revealed text and overlay/AX contracts, distinct from the already implemented gallery-caption spoiler path |
| A11 | P1 | `ChatView.viewDidDisappear` → `ChatBottomArea.cancelActiveRecordingGesture` → `ChatVM.cancelVoiceRecording` deletes the saved preview/WAV on Back because preview keeps `recordingVoiceNote == true`; permission loss uses the same teardown | fixed in `909215a` — preserve on teardown, wait for route-owned persistence and invalidate old UI intents; Simulator preview/trim Back→reopen→relaunch, active-recording Back and explicit Delete passed; live rights mutation/reply fixture remain unverified |
| A12 | P1 | Voice and video coordinators derive outcome destination from the delivered message topic, but an all-messages draft owns `destination.topic == nil` with separate `sendTopic`; store lookups require exact route equality before and after enqueue registration. Both `loadOutcome` helpers also fall back to any draft outcome when the exact temporary-ID record is absent | fixed in `847b838` (worker `2ccdb9b`) — separate delivery key, unique candidate, route+delivery enqueue gates and exact temporary-ID journal consumption. Isolated real-store early/late, all-messages, wrong-ID, ambiguity and relaunch probe passed. Pre-registration crash retains unresolved ownership; automatic recovery remains open |
| A13 | P1 | Voice and video coordinators read current active account after `NotificationCenter.publisher` defers delivery to main; an account switch between posting and delivery can attribute A's outcome/delete to B with colliding IDs | fixed in `c356513` (worker `1eb9d23`) — immutable accepted-update source through generated dispatcher; 15 outcome/delete subscribers migrated, including document cleanup; isolated production-transport probe passed. This does not fix callbacks dropped before publication, A12 correlation or A18 media streams |
| A14 | P1 | `ChatVM.startVoiceFinalization` persists an adopted draft before encoding, but sets enqueue ownership only later; a reopened ChatVM restores it as retryable while the previous owner still encodes/sends; store has no finalization/file reservation | fixed in `bb01b8f` (worker `a8d04c2`) — canonical per-draft/token ownership through encode and actual-ID registration, unique codec outputs, cancellation/join and stale UI fences. Native-codec/store probe and A12 regression pass; production no-send promotion passes. Reinstall proof fails separately at pre-existing A26 |
| A15 | P1 | Video navigation/background/interruption sets preservation intent, then `VideoNoteCaptureSession.cancel` → writer cancellation deletes the current MP4 before adoption; Record More loses the unadopted new segment | fixed bounded lifecycle — navigation joins through `d34eeb3`, video `8b42052`, voice `15871f5`/`fe5de21`; actual codec/private-store lifecycle and send-boundary probes pass. Real OS suspension/audio delivery, hardware UI and live TDLib boundaries remain unverified |
| A16 | P1 | A retained consumed-origin video preview still owns its managed send asset; retry from composer acquires enqueue ownership, but preview Cancel calls `discardVideoNoteAsset` without the retry guard and can remove that in-flight file | fixed bounded handoff in `a72d93b` (worker `44c2c35`) — consumed-retained preview detaches without reclaiming/discarding send-store media, including pending Cancel; unconsumed cancellation and tombstones unchanged. Actual offscreen recorder/native media/isolated store probe passes stale teardown→retry registration; live send/gesture/recording materialization remains unverified |
| A17 | P1 | Video automatic limit reserves `stopRequested` before async finish/UI publication; manual release in this gap still calls finish, gets `recordingUnavailable`, then failure cleanup cancels/deletes the valid near-limit clip | fixed bounded ownership in `e8a0eb1` (worker `6809716`) — one generation-scoped finish owner; competing stop returns no asset, automatic delivery retains authority, recorder operation completions are token-fenced. Actual capture-session/native H.264/AAC probe passes; real camera/limit/gesture/adoption proof remains open |
| A18 | P1 | `TDLib.activate` creates account-labelled range coordinators but passes the same lifetime-global `fileUpdates` subject; retained old-account sources accept new-account files by numeric ID. The lifetime-global delete subject similarly reaches old gallery/PiP owners without provenance | fixed in `76f9998` (worker `b2e33d2`) — immutable per-activation streams, accepted-source fence and inert bootstrap. Real range-source bytes plus retained deletion subscriptions pass A/B/replacement-client collision probe. Actual account switch/system PiP remains unverified; A19 restoration remains open |
| A19 | P1 | `GalleryPictureInPictureCoordinator.presentRestoredGallery` retains messages/owner but rebuilds gallery with mutable shared `tdlib` only, omitting original `actionClient`, `sourceLocation` and `contextIsCurrent`; restore has no account/client guard, and dismissed PiP ownership survives context teardown | fixed in `d8ed16e` (worker `1ea2594`) — frozen account/client/chat/topic/ranges/delete authority, route callbacks and same-tab pagination, every-activation revocation, bounded exactly-once restoration. Isolated context and existing owner probes pass; actual system PiP and action transport remain unverified |
| A20 | P1 | At `176eab9`, `MessageMediaView`/album tiles drop `MessagePhoto/Video/Animation.hasSpoiler`; no production display consumer checks this flag. Photos/previews and eligible videos/FFmpeg animations render before any reveal | needs-fix — per-message/account reveal state, concealed snapshots/preview/AX and playback gating across single/album/reuse/fullscreen transitions; distinct from caption/text spoiler A10 |
| A21 | P1 | `MessagePhoto.isSecret` is lost by `SinglePhotoView.configure(photo:)`; animation paths likewise omit it. Video inline autoplay and export/PiP are gated, but preview/fullscreen presentation still uses the ordinary tap route; only video-note playback calls `openMessageContent` | needs-fix — secret photo/video/animation blur and hold-only presentation, captured-context open/expiry acknowledgment, release/cancel/background teardown and export/transition protection. Existing inline video/PiP/export rejection does not prove secret-media viewing semantics |
| A22 | P1 | `ChatView.updateSnapshot` (1329–1367 at `3b566dd`) captures latest/anchor without checking tracking/drag/deceleration, then unconditionally restores it after asynchronous diffable apply. Reconfigure/rotation completions also reuse a captured anchor without a fresh interaction/revision check | needs-fix — preserve structural layout deltas without rewinding user scroll; invalidate obsolete automatic restoration by interaction/layout generation, distinguish explicit navigation, and verify prepend/edit/media resize/keyboard while dragging and overlapping snapshots. Self-sizing's separate fresh-scroll guard does not cover these paths |
| A23 | P1 | At `19a6f94`, RootVM's non-outcome TD notifications still lose source before main delivery; `updateChatLastMessage`/draft/unread/user handlers mutate current folders by numeric ID. `refreshChat` awaits dynamic `td.getChat` then writes current folders without captured account/client/generation validation; an A response may overwrite B's same-ID chat after switching | partial — Root/list `e1d295e` freezes update/read authority; Chat `df9eb7a` fences 20 typed subscribers and five asynchronous hydration paths. Bounded probes pass. Remaining subscribers, same-epoch ordering and real multi-account RPC races remain open |
| A24 | P1 | At `bb01b8f`, `ChatVM.sendMessage` dispatches by `canEditMessage`; an empty text edit falls through to preserved ordinary text/attachments. A successful edit clears by message ID only, discarding newer typing or a reopened same-ID edit session | fixed in `b18da97` (worker `8aa914f`) — explicit edit intent, immutable payload and session/revision gates on success/error; invalid text edit disabled, empty media caption allowed. Integrated suspended-callback policy probe passes; full ChatVM/UI/server edit remains unverified |
| A25 | P1 | `Utils/Text.swift` maps independent bold/italic to one font, collapses pre/preCode to code and drops quote/mention/custom-emoji identity; loading and saving a formatted message can remove entities unrelated to the edit | needs-fix — semantic attributed-string round trip with UTF-16 ranges, independent formatting and entity payloads; separate from spoiler concealment A10 |
| A26 | P1 | Real own-draft reinstall at `d8ed16e` relocates the app data container: `VoiceNoteDraftStore.loadAllDrafts` rejects persisted absolute URLs and deletes the manifest although its Ogg remains. `VideoNoteFileStore.loadAllManifests` has the same absolute-path filter for MP4/thumbnail | fixed in `8519b33` (worker `2e28fad`) — relative managed filenames, strict legacy container rebasing, retained malformed/missing manifests and migration-write fallback. Isolated voice/video relocation/outcome probes and own voice recovery→reinstall→Discard pass; DEBUG fixture correction `5a87726` keeps production validation strict |
| A27 | P1 | `peerProfileCanChangeInfo` only accepts creator/admin, so eligible group members with `Chat.permissions.canChangeInfo` cannot open or save Edit; restricted-member permissions are also ignored | fixed in `b0db39f` (worker `1a78906`) — shared effective capability, fresh appearance hydration and scoped rights updates; captured actor/account/client plus fresh `getChat`/`getChatMember` before each title/description write. Integrated 25-case policy and delayed-request probe passes; live profile permission/save behavior remains unverified |
| A28 | P2 | `PeerProfileViewController.loadMore` catches without a request-generation fence; A→B→A lets the first A's late error clear the newer A `historyTask` and display a stale error. TDLib continuation is not canceled by task cancellation | fixed in `9cdc6b0` — invalidate request identity before tab cancellation; success/error/cancellation may clear busy state or publish only after consuming their exact registration. Token regression passes A→B→A, obsolete cancellation, retry and duplicate delivery; actual suspended controller/RPC race remains unverified |
| A29 | P1 | `MainView.setAllChatsMuted` re-resolves global `td` between `getChat` and `setChatNotificationSettings`; switching A→B during the read can write A's settings/peer ID through B. FolderView/menu/editor read/write sequences likewise lack frozen action authority | fixed bounded transport in `15f146f` (worker `7513376`) — immutable action client/source, read/write/completion gates, cancellation/attachment checks. Production bulk-helper suspended-read/write probe passes with stale writes=0; cold-launch folder/editor navigation passes. Live account/dismissal mutation races and server writes remain unverified; stale same-account screens still require A30 |
| A30 | P1 | Background ownership release closes clients while suppressing Closing/Closed; foreground activates same account with `notify:false`. Root compares only loggedIn/accountID and retains a ChatVM whose immutable client/location epoch is closed; updates/sends are rejected until Back→reopen | partial — Main `0820359`/`c5d3f8b`; quiescent Chat `494bf56`/`9495f0a` now transfers composer/history and settles anchor/focus. Same-PID Saved Messages background→foreground and deferred emoji-picker Done smoke pass. ForumTopics, Archive, already-open editors and active capture remain deferred; full account/notification lifecycle unverified |
| A31 | P2 | Poll submission times out after 10s and allows another request, but old RPC failure calls `failSubmission(messageID:)` without an attempt token, clearing the newer submission's busy state; timeout callbacks likewise identify only message/source selection | fixed bounded scope — `b7de6ee` freezes per-attempt identity across queued RPC, failure, timeout and authoritative selection reset; production-store probe passes, delayed live RPC/UI remains unverified |
| A32 | P2 | A29 production screenshots at `15f146f` show circular Back/Add and capsule Save controls on Chat Folders/New Folder; those secondary screens use native UIBarButtonItem despite the required classic chrome | needs-fix — audit secondary navigation controls against pinned pre-Liquid chrome; preserve full-width blur/safe-area and accessibility. A zero forbidden-marker scan does not prove UIKit's default runtime appearance |

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
Video source pass at `8268947`: `VideoNoteRecorderViewController`, `VideoNoteCaptureSession`, `VideoNoteAssetWriter`,
`VideoNoteFileStore`, `VideoNoteDraftCoordinator`, `ChatVM` and composer retry/discard callers. References at the pinned current /
pre-Liquid SHAs: `ChatControllerMediaRecording.swift` stop-to-preview (404–475 / 414–482), `ChatController.swift` navigation
(6856–6865 / 5963–5971), `VideoMessageCameraScreen.swift` limit handling (437–479 / 426–468), and
`Camera/Sources/VideoRecorder.swift` (354–373 at both). Positive checks: serial A/V drain, capture-generation/camera retiming,
atomic recording revisions, composition snapshot lifetime and atomic send adoption/removal tombstones. These do not close A15–A17.

Positive source checks: bounded cancellable TGS inflate, copied premultiplied WebP/FFmpeg frames, bounded frame caches, first-frame
fallback; checked C AVIO arithmetic/packet ownership, serialized close/cancel and retained Swift callback contexts. These checks do not
close runtime gaps. P2 follow-ups include TGS parsed-cache byte bounds, custom-emoji metadata eviction, repainting and glyph advance.

Owner/PiP source pass — 2026-10-02 at `909215a`: primary inspected `TDLib.swift` activation/publication (62, 194–218,
306–384), `TDLibVODRangeSource.swift` routing/acceptance (372–376, 814–823, 993–1099), gallery context/release/delete
(905, 934–950, 1348–1407, 1824–1849), owner/delete lifecycle (3946–4033, 4755–4860, 5147–5176) and PiP restoration
(5443–5628). Positive source checks: attachment-token reuse fencing, pending/active PiP retention, timeout identity checks,
exactly-once skip completion and guarded audio-session release. A18/A19 remain source findings, not reproduced system PiP.
Reference: pinned pre-Liquid `GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift` retains its context (75/959), keys hidden
media by account (1060–1068), and restores via its captured expand callback (1093–1104). DirectFetch reads through its captured
resource media store (491/511/637–646). Current full-gallery action/gesture audit remains pending; no infrastructure is copied.

Message-content source pass — 2026-10-02 at `176eab9`: `MessageContentPresentation` exhaustively maps the pinned 104-case
TDLib enum; explicit unsupported/expired/service/excluded-paid paths exist. `MessageCell.configure` connects the classifier to
media, structured supplement, caption and reaction views. This is dispatch coverage, not rendering/action parity. Text still drops
web-preview data; rich/game/story/checklist and detailed service actors/targets remain declared fallbacks. No excluded paid flow is added.
New A20/A21 evidence: `MessageContentView.swift` single dispatch (39–170), photo configure (304–310), album tile dispatch;
`ChatView.showMedia` (1837–1864), inline secret-video guard (2101); gallery caption concealment (329–440), action secret gates
(2042/2714/3144), owner PiP/range restrictions (4006–4019). TDLib `MessageContent.swift` documents spoiler/hold-only contracts
at 1097–1101, 1195–1199 and 1259–1263; `openMessageContent` appears only in video-note viewing. A10 also requires sanitizing
the parent cell's `accessibilityLabel` (MessageView 530–547), not just the child text view.
Reference: pinned current/pre-Liquid `ChatMessageInteractiveMediaNode.swift` detects secret/spoiler state (925/946 vs 923/944),
disables pinch shortcuts (2500 vs 2380) and overlays/conceals media (3094 vs 2948–2988); pre-Liquid lines 923–935 track secret
countdown state. These are source findings; no secret content was opened, sent, revealed or consumed on the user's account.

Initial timeline source pass — 2026-10-02 at `3b566dd`: `ChatVM` uses a raw oldest history ID (853–901), captured client/topic
history routing (3307–3335), album-ID merging and raw child-ID deduplication (3131–3172). `ForumTopicRun.swift` projects separate
message/album/date/topic identities; `ChatView` excludes headers from prefetch/read paths and captures prefetch client+generation
(432–460). Existing pixel anchors, self-sizing mutation depth and fresh scrolling guard (1538–1626) are positive source evidence.
A22 qualifies older claims that every snapshot avoids fighting active dragging: structural apply and asynchronous completion paths
remain exposed. Reference: pinned pre-Liquid `ChatHistoryListNode.swift` stationary-item transaction (4229–4238), and
`Display/Source/ListView.swift` tracking/deceleration state (297–304), deferred transaction state (2124–2194) and tracking-aware
inset repair (3180). Only behavior is referenced; do not port Display. No live pagination/drag proof is claimed by this source pass.

Initial account/list event pass — 2026-10-02 at `19a6f94`: `RootVM+Publishers.swift` resets folders on account notification
(8–17), but non-outcome subscriptions (18–61, 94–119) retain raw payloads. Chat/draft/last-message mutations (142–177) and
`refreshChat` (195–201) need accepted-event/RPC identity. `ChatVM+Publishers.swift` still has raw reaction/permission/topic/new-message
subscriptions: checking the current route alone cannot authenticate a queued event's source. `NotificationCenter.swift` raw helpers
defer delivery without carrying `TdUpdateSource`; A13's scoped helper already supplies the required captured transport seam.
Reference: pinned account-owned `AccountStateManager` streams and `PendingMessageManager` contexts cited for A13/A18 above.
This source audit confirms missing fences, not a live account-switch reproduction; existing account databases were not changed.

Composer/action source pass — 2026-10-02 at `bb01b8f`: edit dispatch/completion (`ChatVM` 1505–1536), edit payload
(2330–2402), semantic entity conversion (`Utils/Text.swift` 34–105), formatting menu and enabled/editable input were checked.
A24 can send an unrelated preserved draft or discard newer typing; A25 loses semantic formatting. Source references at the pinned
current/pre-Liquid SHAs: `ChatControllerLoadDisplayNode.swift` empty-edit return (2267–2283 / 2155–2171),
`TextFormat/Sources/ChatTextInputAttributes.swift` independent keys (12–29), `GenerateTextEntities.swift` (149–183 / 148–182).
Positive source checks: transition temporary/final/failure aliases, canonical album lookup, bounded cleanup and forward destination/
comment capture with ambiguous-result retry gating. P2 gaps: picker sticker/GIF dismisses before a source-cell snapshot reaches the
transition; slow draft-clear RPC can outlast the five-second snapshot lifetime. Photo partial-result semantics remain a proof gap,
not a reproduced partial-send defect. No live send, edit, keyboard or flight proof is claimed.

Profile/gallery source pass — 2026-10-02 at `d8ed16e`: member/admin pagination and tag authority, self/chat edit,
avatar roles/history/video visibility, shared-media pagination, gesture arbitration, rotation, source-transition identity and canceled
transition cleanup were reviewed. A27 permission gates occur in `PeerProfileControlsViewControllers.swift` (9–19, 1110–1118)
and `PeerProfileViewController.swift` (1017–1022, 1577); A28 late-error completion at 1151–1161. Pinned references:
`PeerInfoData.swift` current/pre (2395–2427 / 2158–2191), `TelegramCore/Sources/ApiUtils/TelegramChannel.swift`
(209–226 / 207–224), `GalleryControllerNode.swift` (561–618 / 491–559). TDLib `setChatTitle`/`setChatDescription`
require effective change-info permission; its async continuation does not itself cancel the underlying completion.
A20/A21 remain separate. No new gesture P0/P1 was confirmed by this source pass; runtime parity is not established.

Account/list/shell source pass — 2026-10-02 at `cf885b1`: account registry uses UUID directories and atomic saves; retirement
waits for client closure before deleting an explicitly removed account directory. Settings/login expose add/switch/logout; no such
operation was performed here. MainView chrome constraints span leading/trailing and safe-area top/bottom. A29 evidence:
`MainView.swift` 484–508, `FolderView.swift` 433–445/527–545 and `ChatFolderManagementViewController.swift` 383–392.
Pinned `ChatListController.swift` current/pre (1187 / 1961) mutates through its immutable account context (98 / 91).
A30 evidence: `BetterTGApp` 151–159, `TDLib` 124–166/348–378, `RootView` 43–46, RootVM Ready subscription and immutable
ChatVM location/client guard. Pinned `AccountContext.swift` current/pre (117–118 / 115–116) and `ApplicationContext.swift` 106
retain account-bound ownership. A19's new client-change stream revokes PiP correctly but does not rebuild retained chat routes.

A30 bounded production smoke on `b18da97`, audit Simulator, same PID `79320`: Saved Messages → idb HOME → tap observed
BetterTG icon returns the same chat. Identical hold→lock gesture produces no recording; Back→reopen then the same gesture shows
`Voice recording locked, 36.62`. Explicit Cancel removes only that agent-created control recording; recording store is empty, and
the older A26 orphan Ogg remains backed up. Captures: `.build/ui-probe-evidence/astra-a30-lifecycle`. A bounded idb log stream
yielded no app records and an idb Python timeout-cleanup diagnostic; it is not evidence of an app crash or a client-ID log.
No actual send, logout or account switch was used. Source tracing supplies the client-replacement cause; UI proves the gesture regression.
Profiles usually auto-pop on the later account-metadata notification and can return to the same stale chat; a permanent profile freeze
is not claimed.

Structured-action source pass — 2026-10-02 at `cf885b1`: contact detail/call, location snapshot/live label/external Maps,
file/audio reuse, poll/quiz restriction/selection/result/explanation paths, dice sticker/fallback, selected-message deletion,
reaction availability and pin-property refresh were traced to ChatVM/captured-client actions. A10/A20/A21/A23 remain applicable.
New A31 is confined to poll in-flight ownership (`MessageStructuredContentView` 56–112, `ChatVM.submitPollAnswer` 1046–1066).
Pinned pre-Liquid `ChatController.swift` 3409–3440 keys in-progress poll actions and their request lifetime by message. No SignalKit
is imported. This source pass does not prove every content's real rendering/action behavior; no polls or external apps were opened.

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
  B01 for the original database or prove sticker playback. The later explicit continuous-work request authorizes further slices.

### Voice lifecycle preservation proof — 2026-10-02

- A11 scope: navigation/permission teardown stops capture and preview without calling explicit discard. Main-actor registration
  retains canonical PCM/trim/adoption work and makes a reopened account/chat/topic route await it. A lifecycle generation rejects
  pre-suspension permission/resume/send/trim-audio continuations even after UI re-enablement. A forced teardown trim save never
  starts preview audio. Recording and send storage formats, route/reply/caption/waveform/revision contracts remain unchanged.
- Independent delta review identified the reopen barrier, stale intent revival and forced-trim autoplay gaps; all three were
  repaired. A12–A14, video lifecycle A15 and system interruption handling are not claimed fixed by this slice.
- One SwiftFormat invocation covered the five changed Swift files. Final warning-free `./build.sh build` log:
  `.build/logs/xcodebuild/build-Debug-20261002-150301-32416-21283.log`; no warnings/errors in the full output.
- `./build.sh run --skip-build --simulator-id 59EB535C-3610-41A2-AB68-53A9467DC24B --
  -media-probe-voice-preservation -ui-smoke-voice-gestures`, iPhone 17 Pro / iOS 26.5, PID `36834`.
  The user-authorized Simulator reaches real Saved Messages. The deterministic barrier/epoch probe reports restore-waits,
  canonical-revision, account-isolation, barrier-cleanup, suspend-invalidates-intent, reenable-keeps-old-intent-invalid and
  new-intent-allowed. Output: `.build/ui-probe-evidence/astra-voice-preservation-final-probe/voice-preservation-probe.txt`.
  This tests production coordination primitives, not an injected full ChatVM PCM-save race or live rights mutation.
- Production idb flow: hold→lock→pause, trim `0…21.0189435044s`, Back→reopen and wrapper relaunch all retain the same local
  draft `A4895271-1B10-484A-BD3D-8A7D74D60BB9`, media filename and edit revision 1. Sorted canonical manifest SHA-256 after
  Back and relaunch: `63d4ca98ab895c0f2013986a48f564e5c4b03edb45ed7f6a6e128b3c3ab9abd2`.
  Evidence: `.build/ui-probe-evidence/astra-voice-after-{back,relaunch}/`, `astra-voice-after-relaunch.png` and filtered hierarchy.
  The final build again restored trim `0:00.0…0:21.0` with Play, not active playback. Reply was nil; reply preservation is source-only.
- A second real hold→lock followed by Back during capture produced paused `27.6s` preview after reopen, not a continuing recorder.
  Manifest/WAV `5753F35D-1BE7-43F6-8713-C20DE301B67B` were present; proof is in
  `.build/ui-probe-evidence/astra-voice-active-back/` and `astra-voice-active-back.png` (visually inspected).
  Explicit Cancel/Delete removed each agent-created draft and WAV; the recording-draft directory was empty after both deletions.
  No messages were sent, no chat rights changed, no user drafts removed, no database reset and no Simulator shutdown occurred.

### Accepted TDLib update provenance proof — 2026-10-02

- A13 worker `1eb9d23c75a335defd5a2df2274d9b6dc2504aaa` was independently reviewed and integrated as `c356513`.
  `TDLib.handle` captures account UUID/client ID into immutable notification userInfo; `td.py` generates exactly one post with
  unchanged name/raw object. Opt-in scoped subscribers extract payload/source before scheduler delivery and reject missing source.
  Voice/video durable cleanup and selected-document ownership use event account; ChatVM/forum UI additionally match frozen client.
  All 15 subscribers of send-success/send-failure/delete in these five consumers were migrated; legacy subscribers remain compatible.
- Worker warning-free build: `.build/logs/xcodebuild/worker-A13-build-Debug-20261002-152038-71499-21293.log`.
  Primary SwiftFormat covered all 11 changed Swift paths in one invocation (`0/10` changed, generated file excluded by config).
  Primary build passed without warnings in `.build/logs/xcodebuild/build-Debug-20261002-152748-427-24895.log`; generated output
  stayed unchanged after wrapper regeneration. The first primary attempt stalled before compilation while clang wrote to its
  SDK-discovery pipe; only that owned xcodebuild was interrupted, then the unchanged wrapper retry passed in 11s. Diagnostic:
  `.build/ui-probe-evidence/astra-a13-build-diagnostic/clang-81316.sample.txt`. No cache or Simulator reset was used.
- Wrapper launch on authorized Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iOS 26.5, PID `1577`, with
  `-media-probe-update-source`: `.build/ui-probe-evidence/astra-integrated-update-source/update-source-probe.txt` reports generated
  dispatch, delayed A→B delivery, colliding-ID isolation, old-client UI rejection, same-account durable ownership, unscoped rejection,
  exactly-once raw legacy payload and permanent-delete guards all passed. The real Saved Messages row remains accessible by idb.
- Probe scope: real generated dispatcher and Combine transport with an isolated NotificationCenter/in-memory consumers. It does
  not switch real accounts, touch user stores or exercise TDLib server outcomes. Production subscriber migration was source-reviewed.
  The existing active-client gate still drops callbacks arriving after a switch; safe inactive-client outcome recovery remains open.
  A12 route/temporary-ID matching, A14 finalization leases and A18/A19 VOD/PiP are unchanged.

### VOD main-track and duration-authority proof — 2026-10-02

- A04 worker chain `23b1e49` → `61bb5e3` → `e87ef9c` was independently reviewed and integrated as
  `83103ba` → `14a01c5` → `ef8f4ba`. C selects explicit video end before audio, clips the longer audio tail and preserves persistent
  windows/final video frames. Explicit duration travels to Swift separately from container estimates. At real EOF, observed frame
  ends resolve estimates in either direction; initialized seek cursors cannot invent media duration. Verified terminal summaries
  cancel both watchdogs. An unknown end with no observed main frame or explicit metadata fails safely, not with a fabricated EOF.
- Reference: pinned current/pre-Liquid `MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift` chooses `video ?? audio`
  (546/578 current, 547/579 pre-Liquid). No decoder, player-clock, queue/cache/lease architecture or dependency version was replaced.
- Native before/after evidence: `.build/ui-probe-evidence/astra-a04-native/` and `astra-a04-fallback/`, including harness, pinned
  fixtures, source snapshots and commands. Host FFmpeg 9.0.2 proves video 2s/audio 10.008s ends at 2s with all 20 video frames;
  missing-video-duration container estimates 8s/20s both resolve to 12s with all 144 frames, seek 11s begins at 11s, and seek 25s
  emits no frames but observes true EOF at 12s. Longer-video/shorter-audio, origin, standard and audio-only regressions passed.
  These host runs are not Apple media-clock proof.
- Worker final warning-free log: `.build/logs/xcodebuild/worker-A04-build-Debug-20261002-152136-73961-20174.log`.
  Primary one-call SwiftFormat covered four changed Swift files (`0/4` changed); warning-free `./build.sh build` at `ef8f4ba`:
  `.build/logs/xcodebuild/build-Debug-20261002-153032-2363-12736.log` (18s).
- Authorized iPhone 17 Pro / iOS 26.5 Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, wrapper/idb only:
  PID `2903` with `-media-probe-vod-main-track -media-probe-vod-ffmpeg-decode` passed both. Main-track output is
  `.build/ui-probe-evidence/astra-integrated-vod-main-track/vod-main-track-probe.txt`; decoder output is
  `astra-integrated-vod-decoder/vod-ffmpeg-decode-probe.txt`. Explicit 2s EOF and known/initial seek 6→2s, both estimate variants,
  seek 25→12s, persistent sessions, cleanup and bounded queues passed. Decoder retained 24 VP9 frames/101 Opus buffers,
  95,641 stereo sample frames, monotonic PTS, 3 persistent pumps/one open/zero rollover seeks, sparse unequal-track handling,
  cancellation/supersession, SWR drain and close-waits.
- PID `3401` with `-media-probe-vod-ffmpeg-controller`: `.build/ui-probe-evidence/astra-integrated-vod-controller/`
  `vod-ffmpeg-controller-probe.txt` reports stable pause, rate 1.5, offscreen cancellation/intent, last-seek-wins, 10 persistent
  windows/one open/zero rollover seeks, EOF, offline/retry/clamp and zero renderer errors, plus every new main-track assertion.
  idb still sees the real Saved Messages row afterward. No sends, account switch, data reset or Simulator shutdown occurred.
- Proof limit from independent delta audit: mixed-metadata fixture is 84,225 bytes, below the 2 MiB range fetch. Auto-fulfillment plus
  `limit != 0` proves finite request shape, not playback before the complete small file is cached. Existing lookahead still treats
  fallback duration as authoritative; no controller blocker was proven because original decodeStart and actual accepted frames
  advance playback independently after the initial scan. Follow-up: reconcile lookahead duration authority and test >2 MiB media
  with unavailable/delayed tail ranges, seek beyond an estimate and explicit incomplete-byte-coverage assertions. Live Telegram
  streaming and active system PiP remain unverified; do not promote this bounded proof to global VOD parity.

### Exact media-draft delivery and client streams — 2026-10-02

- A12 worker `2ccdb9b` integrated as `847b838`: `ChatDraftDeliveryKey` freezes account/chat/send topic independently of the
  owning UI route. Stores reject simultaneous enqueue by either route or delivery, require a unique outcome candidate and consume
  early evidence only after exact temporary-ID registration. Registration is persisted before cleanup; arbitrary-ID fallback is
  removed. Legacy account binding preserves the base route. Existing JSON contracts and recording-origin ownership remain intact.
- Reference: pinned current/pre-Liquid `TelegramCore/Sources/State/PendingMessageManager.swift`, account-owned manager
  (218/251 current; 213/239 pre-Liquid), immutable message request ID (192/187), pending-ID contexts (409/258), thread context
  (640/462). TDLib 1.8.66 `updateMessageSendSucceeded/Failed`, `oldMessageId`, delivered `Message.topicId`; no infrastructure port.
- Primary one-call SwiftFormat covered all eight files (`0/8` changed); warning-free wrapper build:
  `.build/logs/xcodebuild/build-Debug-20261002-153825-17942-30766.log` (9s). Worker log is preserved with `worker-A12-` prefix;
  scope/commands/limits are in `.build/ui-probe-evidence/astra-a12-worker/README.md`.
- Safe Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, wrapper PID `18527`, `-media-probe-draft-outcomes`:
  `.build/ui-probe-evidence/astra-integrated-draft-outcomes/draft-outcomes-probe.txt` passed voice+video, ordinary/explicit/all-messages
  early/late success/failure, original route, wrong account/chat/topic/ID, duplicate old manifests, both enqueue gates, exact-ID
  relaunch, unresolved pre-registration crash, legacy base-route migration and unrelated draft/file preservation.
  This uses real store methods and disk manifests in disposable UUID directories with synthetic media bytes; no server sends.
- A18 worker `b2e33d2` integrated as `76f9998`: every activation owns separate file/delete subjects with immutable account/client
  provenance. Retained publishers cannot follow later account/client replacement. Bootstrap remains inert; A13 and the active-client
  gate are unchanged. All three deletion consumers were source-checked. The sole cherry-pick conflict retained both DEBUG probe hooks.
- Reference: pinned current/pre-Liquid `AccountStateManager.swift` (322–324/308) and `ChatListSearchListPaneNode.swift` (4814/4650)
  use account-owned deletion streams. TDLib `updateFile`, `updateDeleteMessages`; range clients and numeric-ID API stay unchanged.
- Primary one-call SwiftFormat covered all three A18 files (`0/3` changed); warning-free wrapper build:
  `.build/logs/xcodebuild/build-Debug-20261002-154003-19429-13561.log` (11s); worker log preserved with `worker-A18-` prefix.
- Integrated PID `20467`, `-media-probe-client-streams -media-probe-update-source -media-probe-draft-outcomes`: all passed.
  `.build/ui-probe-evidence/astra-integrated-client-streams/client-streams-probe.txt` reads distinct real 64-byte files through retained
  A/B/replacement-client range coordinators with identical file IDs and observes isolated deletion subscriptions. Own-stream byte arrival
  is the ordering barrier; unexpected backend fetch fails. Stale/nil provenance and bootstrap events are rejected.
  `astra-integrated-client-provenance/update-source-probe.txt` repeats A13 generated-dispatch/delayed-delivery proof;
  `astra-integrated-client-drafts/draft-outcomes-probe.txt` repeats A12 on the combined product. Real Saved Messages remained visible
  before installs; no account switch, user-store reset, message send or Simulator shutdown occurred.
- Limits: isolated stream/store probes are not live multi-account server delivery or active system PiP. Legacy voice/video codec probes
  were updated and compiled but not rerun here; the new probe avoids their shared-store cleanup paths. Crash before exact ID registration
  preserves an unresolved enqueue, not automatic recoverability. A14 canonical finalization ownership, callbacks rejected by the inactive
  client gate, A15–A17 video lifecycle and A19 restoration remain open.

### Canonical voice finalization and PiP context proof — 2026-10-02

- A14 worker `a8d04c2` integrated as `bb01b8f`. Six Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-155910-46801-26110.log` (14s). Worker log is copied with `worker-A14-` prefix;
  design and proof limits: `.build/ui-probe-evidence/astra-a14-worker/README.md`.
- Voice store claims canonical runtime ownership before encoding, fences stale snapshots/tokens, uses unique attempt outputs and
  persists the accepted temporary ID before UI-generation checks. Native cancellation is joined before ownership release; preflight
  failures can retry, ambiguous post-RPC failures retain unresolved ownership. Metadata/delivery contracts and A12 gates stay intact.
  Current/pre-Liquid `ChatControllerMediaRecording.swift` (344–356, 735–760 / 354–366, 735–766) and
  `PendingMessageManager.swift` (218–251, 409–438 / 213–239, 258–282) anchor preserved ownership and captured send context.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `47929`:
  `-media-probe-voice-finalization -media-probe-draft-outcomes` passed. Results in `astra-a14-primary/voice-finalization-probe.txt`
  and `astra-a14-draft-regression/draft-outcomes-probe.txt` under `.build/ui-probe-evidence`. Real native Ogg encoding, suspended
  worker/RPC gates, duplicate claim/discard rejection, stale token/adoption, exact-ID outcome, pre-registration retention,
  process-local lease recovery and unrelated-file preservation run against disposable isolated stores. This does not send messages.
- Production UI on `bb01b8f`: empty recording/send stores; own hold→lock→pause yielded a 42.06s preview. The existing DEBUG
  `-ui-smoke-voice-preview-send` bypassed the send RPC after real promotion/encoding. Own draft
  `CDD62EC0-0614-4481-B007-119AD74DD113` became `isEncoded=true`, duration 42, no enqueue time/temp ID. Manifest SHA256
  `bbf6973377392f25435894ca0bf6423deb279d1600cb2261b597cca8021b6fe4`; captures and manifest/Ogg backup are in
  `astra-a14-ui`. The no-send alert intercepted Back, so navigation-during-encode is not claimed by this UI sequence.
- Reinstall to combined `d8ed16e` changed the container from `CC9310EE…` to `D630B63A…`; the loader deleted this manifest,
  left the Ogg, and restored an empty composer. `before-relaunch`/`after-relaunch` plus `restored.png` reproduce A26. This is a
  pre-existing absolute-URL persistence defect, not passing relaunch proof. Only an agent-created draft was affected; no user draft
  was deleted. Its backup remains available for recovery and the follow-up test. Recording-preview relative storage is separate.
- A19 worker `1ea2594` integrated as `d8ed16e`. Five Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-160148-52841-23853.log` (20s); worker log copied with `worker-A19-` prefix.
  Freeze playback client/location/ranges/deletion stream, preserve route callbacks separately, rebind only the originating profile
  tab, revoke on every client activation, and bound each restoration completion to one terminal callback. Revoked pending/active
  PiP retains its controller through the stop barrier. References: pinned `UniversalVideoGalleryItem.swift` current context
  734–754/restoration 889/retained navigation 3150–3214; pre-Liquid 938–958/1093. No Telegram infrastructure was copied.
- Combined PID `55486`, `-media-probe-pip-context -media-probe-gallery-owner -media-probe-voice-finalization
  -media-probe-draft-outcomes`: all passed. `astra-a19-context/pip-context-probe.txt` covers frozen topic/nil-topic authority,
  same owner/view, route loss, same/changed-tab pagination, account/client replacement, pending/active stop, no stale reattach and
  exactly-once completion. `astra-a19-owner/gallery-playback-owner-probe.txt` repeats real AVFoundation/FFmpeg owner handoff,
  range/session continuity and lifecycle/adapter checks; voice/draft regressions are in `astra-a19-voice-regression` and
  `astra-a19-draft-regression`. Probe context uses injected client identity; actual TDLib action transport and real
  `activate(notify:false)` are source-reviewed, not server/lifecycle-exercised. `pip-supported=false`: active system PiP still
  requires a capable device. Marker scan over production/dependencies is empty; no Simulator shutdown or account reset occurred.

### Edit-mode safety proof — 2026-10-02

- A24 worker `8aa914f` integrated as `b18da97`. Primary reviewed the entire policy/probe and all edit-session assignment sites.
  `ChatVM` dispatches explicitly between ordinary/invalid-edit/edit, captures the message/formatted payload, and checks session,
  text revision, task cancellation and current location after request completion. Closing Edit preserves the ordinary reply;
  newer typing or a reopened same-ID session survives an old success/error. Semantic entity conversion A25 remains unchanged.
- Six Swift files formatted in one invocation; warning-free primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-161023-77945-13703.log` (10s). Worker log copied with `worker-A24-` prefix;
  `.build/ui-probe-evidence/astra-a24-worker/README.md` preserves scope and reference notes.
- Same authenticated audit Simulator, PID `79320`: `-ui-probe-composer-edit -media-probe-voice-finalization
  -media-probe-draft-outcomes` all pass. Results are under `.build/ui-probe-evidence/astra-a24-primary`, `astra-a24-voice`,
  `astra-a24-drafts`. Edit probe executes the production submission/token policy with suspended callbacks: zero ordinary sends
  for invalid edit, immutable payload, A→B→A revision, same-ID reopen, caller completion-delivery fence, cancellation, unchanged
  success and empty media caption. It uses counters and fixtures, not a real ChatVM, keyboard, selected-attachment view or TDLib
  server edit. Production wiring/disabled action is source/build-proved only. No account data or messages were changed.

### Send-draft relocation and list-action authority proof — 2026-10-02

- A26 worker `2e28fad` integrated as `8519b33`; five changed Swift files formatted together. Primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-161828-25210-228.log` passed without warnings (12s).
  Both stores persist filename-only references and resolve them against the current store. Legacy rebasing permits only the
  app-container UUID to change; wrong owner/name, external/traversal/symlink paths are rejected. All canonical/list loads use
  the resolver. Invalid/missing manifests survive for recovery and protect owned files from orphan pruning; failed legacy
  rewrite still returns the valid runtime draft. Enqueue IDs/outcomes, route/reply/caption/waveform, video thumbnail/origin and
  removal tombstone contracts are unchanged. Reference: pinned current/pre-Liquid `MediaBox.swift` 228–241/491–493 derives
  resource paths from the current base directory; no Postbox code was imported.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `27534`:
  `-media-probe-draft-relocation` passes real isolated stores across legacy/relative × move/copy, raw/encoded/token voice,
  canonical-before-list/stale adoption, outcome authority, video thumbnail/origin/tombstone, malformed/missing/symlink paths
  and injected migration-write failure. Result: `.build/ui-probe-evidence/astra-a26-primary/draft-relocation-probe.txt`.
  A14/A24 regressions pass in `astra-a26-voice`/`astra-a26-edit`. A12 initially fails in `astra-a26-drafts`: its DEBUG encoded
  voice fixture had an extensionless input, persisted as `.wav`, unlike production encoded `.ogg`. Worker `9dce6fc`, integrated
  as `5a87726`, corrects only fixture filenames and diagnostic stages; production ownership validation is not relaxed.
  One Swift file formatted; warning-free build `build-Debug-20261002-162317-68150-27789.log` (8s). PID `71109` repeats A26/A12
  successfully in `astra-a26-final-relocation`/`astra-a26-final-drafts`. Historical failure output is retained.
- Production recovery uses only own draft `CDD62EC0-0614-4481-B007-119AD74DD113`: restore its backed-up legacy JSON beside
  the still-existing Ogg, then open Saved Messages. Retry appears and canonical loading migrates the reference to a filename.
  All metadata except the intended URL change matches the backup; Ogg SHA256 remains
  `c05b255f8c03e0983da8cecef40a4777cdc9dbf08b2b29033b8b3d9d69d0ae33`. Another wrapper install (`5a87726`, PID `71109`)
  preserves identical relative JSON/Ogg and shows Retry. Long-press → **Discard Voice Message**, not Retry, removes this own
  draft through production UI. Send/recording voice stores are then empty and the mic returns. Recoverable backups, migrated
  and reinstalled files/captures: `astra-a26-ui` under `.build/ui-probe-evidence`. No message was sent or user draft removed.
  Real video reinstall remains unverified; the isolated video store probe is not camera/server proof.
- A29 worker `7513376` integrated as `15f146f`; six Swift files formatted together. Primary warning-free wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-162551-79894-26406.log` (15s). Main/folder/editor actions capture one controller
  source/client, gate reads and writes before/after suspension, stop stale bulk loops and fence late UI delivery. Covered
  parent controllers retain legitimate pushed-picker authority; stale chat row navigation remains available for recovery.
  Reference: pinned `ChatListController.swift` current 98/1187, pre-Liquid 91/1961 uses captured account context.
- Combined PID `99924`: `-ui-probe-list-action-authority -media-probe-draft-relocation -media-probe-draft-outcomes
  -media-probe-voice-finalization -ui-probe-composer-edit` all pass. Results: `astra-a29-primary`, `astra-a29-relocation`,
  `astra-a29-drafts`, `astra-a29-voice`, `astra-a29-edit`. A29 runs the production bulk helper with suspended fake RPCs:
  A→B/colliding IDs, replacement client, detached owner, cancellation and unscoped source produce no new writes; late writes
  deliver no old UI result; current errors and continued bulk behavior remain intact. UIKit attachment is injected here,
  not proved by this probe. Read-only production UI opens Settings, then All-tab Edit Folders → populated Chat Folders →
  empty New Folder → Back → Back to All. Settled screenshots `astra-a29-primary/current-screen.png` and `new-folder.png`
  confirm the two authority-gated pushes. An initial AX-only check falsely looked like a no-op: idb returns generic native
  navigation groups without those labels, and the earlier screenshot caught the outgoing menu transition. No folder/account/
  server mutation was attempted. Cold-launch attachment works; live account/dismissal mutation races still need real proof.
  Production/dependency prohibited-marker scan is empty, but these screenshots expose secondary chrome gap A32.

### Effective group profile permission proof — 2026-10-02

- A27 worker `1a78906` integrated as `b0db39f`; primary reviewed both production controllers, shared policy/authorization and
  complete probe. Basic-group admins keep all applicable rights; ordinary members use default `canChangeInfo`; restricted
  supergroup members require membership and both effective/default rights. Supergroup admins retain allowed member rights;
  broadcast channels still require creator/admin authority. Self-profile editing is unchanged; owned-bot editing is not added.
- Fresh `getChat` + `getChatMember` on appearance closes a real entry gap: ChatVM's live permission cache does not update
  `CustomChat.chat.permissions`. Capability state owns its own source/revision, consumes only scoped permission/group updates,
  and rejects an older refresh after a rights event. Unrelated title/photo metadata no longer owns capability state. Each title
  and description write independently rereads permission and verifies source/actor/returned IDs; a revoked second write is
  blocked while existing partial-success handling is preserved. Server authorization remains authoritative; these reads are not
  an atomic permission transaction.
- References: pinned current/pre-Liquid `PeerInfoData.swift` 2395–2427/2158–2191 and
  `TelegramCore/Sources/ApiUtils/TelegramChannel.swift` 209–226/207–224. TDLib `022d6020` `Chat.permissions`,
  `ChatMemberStatus`, `ChatPermissions`, `setChatTitle` and `setChatDescription` contracts were checked directly.
- All five Swift files formatted together; warning-free primary wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-164302-10912-6908.log` (10s). Worker proof README is copied to
  `.build/ui-probe-evidence/astra-a27-worker/README.md`, build log with `worker-A27-` prefix.
- Audit Simulator, PID `11755`: `-ui-probe-profile-info-permissions` passes 25 policy cases, fresh appearance capability,
  scoped live changes/stale refresh, per-write revocation, wrong account/client/actor/chat, cancellation and delayed completion.
  Result: `.build/ui-probe-evidence/astra-a27-primary/profile-info-permissions-probe.txt`. Production helpers run against
  suspended injected reads/writes; no real profile controller permission change or server save is claimed.
  A29/A12/A26/A14/A24 regressions all pass in `astra-a27-list`, `astra-a27-drafts`, `astra-a27-relocation`, `astra-a27-voice`,
  `astra-a27-edit`. No real profile/account/message mutation. Marker scan remains empty; A32 visual chrome remains open.

### Foreground root-list restoration proof — 2026-10-02

- A30a worker `b8d8432`/`469bad4` integrated as `0820359`/`c5d3f8b`. Accepted-source readiness clears on activation/background;
  obsolete clients cannot announce readiness. Navigation replaces only opted-in Main entries for the same account, with exact
  stack/source/generation checks and transition/modal deferral. RootVM must already match the account; its scheduled update retries
  restoration. Account switches and unrelated route objects retain their existing handling. Notification-service ownership is unchanged.
- Main carries selected folder, search query/focus and per-folder chat-ID/pixel anchors. Restore waits for current diffable completion
  and usable layout; newer query/drag invalidates it. Fresh folder object identities rebuild children without resetting their viewports.
  Chat, ForumTopics, Archive and already-open folder editors are deliberately not rebound; A30 remains open there.
- References: pinned current/pre-Liquid `ChatListUI/Sources/ChatListController.swift` 4039–4093/3969–4019 selected-filter preservation
  and 4676–4700/4620–4646 content-ready search; BetterTG adapts these contracts to UIKit/TDLib client epochs.
- All ten initial Swift files formatted together; primary build `build-Debug-20261002-164821-26680-8524.log` passed (19s).
  Model-ready follow-up formatted both files, build `build-Debug-20261002-165126-73786-13702.log` passed (9s), both without warnings.
  Earlier `build-Debug-20261002-164734-18341-15729.log` records a premature build of an unresolved App-hook cherry-pick conflict;
  both hook registrations were retained before these clean builds. Worker logs have `worker-A30a-`/`worker-A30a-model-` prefixes.
- Authenticated audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro/iOS 26.5, PID `74615`, `c5d3f8b`:
  `-ui-probe-client-restoration` passes readiness, A1→A2→A3/stale/account/stack/transition/model fences, retained chat identity,
  production UIKit viewport capture/restore, prepend/missing/clamp and delayed-layout/query/drag checks. Result in
  `.build/ui-probe-evidence/astra-a30a-primary`; six prior permission/action/store/edit regressions pass in `astra-a30a-regressions`.
- Production smoke: scroll groups → HOME → app icon; same PID, selected group folder and visible peer-row Y positions preserved.
  Long-press group tab → Edit Folder opens the real authority-gated editor; Back without Save. A second cycle preserves the own empty-result
  search query and focus: typing `7` without another tap appends to the restored query. Software keyboard stays hidden; no keyboard-layout
  claim. Own search was cleared with Close. Visually inspected captures under `astra-a30a-ui`: `groups-scrolled.png`,
  `groups-restored.png`, `folder-editor-restored.png`, `search-before-background.png`, `search-restored.png`;
  `search-restored-typing.png` plus AX readback records retained first-responder input. No real message/folder/account mutation.

### Single video capture finish-owner proof — 2026-10-02

- A17 worker `6809716` integrated as `e8a0eb1`. Capture contexts carry immutable preparation generation and one manual/automatic
  finish owner through native completion and MainActor delivery. Duplicate/competing manual Stop returns nil; it cannot convert an
  automatic success into failure cleanup. Cancellation/replacement cleans only undelivered owned output; a delivered asset survives
  later capture cancellation. Missing callback cleans its own output. Recorder tasks clear only their operation token; accepted
  automatic finish fences late start/duration/stopping updates, including the preparing/Record More interval.
- Reference: pinned current/pre-Liquid `Camera/Sources/VideoRecorder.swift` 367–376 reserves stopped state before finishing and
  delivery; `LegacyInstantVideoController` guards completion/dismissal. A15 preservation and A16 consumed-preview ownership are unchanged.
- Five Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-165751-81511-11272.log` (23s). Worker final log copied with `worker-A17-` prefix;
  `.build/ui-probe-evidence/astra-a17-worker/README.md` records its scope.
- Audit Simulator, PID `1196`, `e8a0eb1`: `-media-probe-video-note-finish` passes actual capture-session finish/cancel methods with
  a real H.264/AAC writer. Suspended native-finish and delivery windows cover competing/duplicate Stop, cancellation, replacement,
  missing callback, exactly-once error and retained transferred output. Actual recorder operation helpers cover stale cleanup and
  late preparing/start/duration/stopping. Result and seven A30a/A27/A29/A26/A12/A14/A24 regressions all pass under
  `.build/ui-probe-evidence/astra-a17-primary`. Fixtures are isolated; asset move simulates adoption, not the production store transfer.
  Hardware camera/microphone, full-duration limit, physical gestures, real adoption and server send remain unverified.

### Composer-transfer foundation and video-preview handoff proof — 2026-10-02

- A30b1 worker `946dc02` integrated as `ef558ec`. An in-memory value snapshot separates ordinary compose/edit/reply/quote intent
  from mutable CustomMessage objects; images/documents retain IDs. One-shot transfer requires exact account/chat/topic (nil remains
  distinct), a new current client and unchanged quiescent owner state. Cancel/mismatch/failed retirement retains old ownership;
  commit synchronously retires it before constructing the new owner. ChatVM seeds local dirty intent before publishers/server draft
  hydration and fences retired location use/deinit file deletion/Media dismissal. No persistent schema or TDLib API change.
- Navigation does not yet call this factory. Active/pending voice/video/send/import-sensitive work must stay excluded until its
  ownership barriers are implemented; ordinary-controller picker/transition checks belong to A30b2. Before enabling replacement,
  navigation must accept the transaction before irreversible retirement and process Main plus Chat in one ready cycle.
- References: pinned current/pre-Liquid `ChatInterfaceState/Sources/ChatInterfaceState.swift` 513–523/514–524 and 612–618/565–571
  separate compose/edit/reply/media state. Four Swift files formatted together; primary build
  `.build/logs/xcodebuild/build-Debug-20261002-171549-4184-7097.log` passed without warnings (16s).
  Worker final log copied with `worker-A30b1-` prefix. Audit Simulator PID `4968`: `-ui-probe-composer-restoration` passes actual
  value/transfer/lifetime helpers, isolated selected files, account/topic/client fences, unchanged/busy/cancelled/reentrant state,
  failed-retirement retry, detached mutable message and old-deinit cleanup=0/new-owner cleanup=1. Five readiness/edit/media regressions
  pass beside the result in `.build/ui-probe-evidence/astra-a30b1-primary`. No actual ChatVM construction in this probe:
  seed order and production cleanup wiring are source/build proof only, not foreground Chat recovery.
- A16 worker `44c2c35` integrated as `a72d93b`. Recorder reuses enqueued cleanup when retained result says `originConsumed=true`:
  clear local ownership and dismiss, leaving retry/discard with composer. Cancel during submission cannot discard the transferred
  file; only its obsolete error is suppressed. Unconsumed local preview/Cancel and send-store removal tombstones are unchanged.
- References: pinned current/pre-Liquid `LegacyComponents/Sources/TGVideoMessageCaptureController.m` 1109–1115/1113–1119
  and `LegacyInstantVideoController.swift` 215–257/216–258 transfer capture into outgoing resource ownership. Three Swift files
  formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-171743-5488-28712.log` passed without warnings (8s).
  Worker final log and README preserved with `worker-A16-` prefix and `.build/ui-probe-evidence/astra-a16-worker/README.md`.
- Audit Simulator PID `6029`, `a72d93b`: `-media-probe-video-note-submission-ownership` passes six actual offscreen-recorder
  scenarios with isolated VideoNoteFileStore and native MP4 fixtures. Consumed-retained, Cancel during submit, stale navigation result
  and enqueued paths preserve canonical media/manifest through obsolete Cancel/deinit; retry acquires ownership and exact temporary-ID
  registration succeeds. Unconsumed preview and pending Cancel still delete the local asset once. Seven A17/A30b1/A30a/A24/A14/A12/A26
  regressions pass under `.build/ui-probe-evidence/astra-a16-primary`. No real messages sent, user stores changed or capture hardware
  started. Persisted-recording materialization, ChatVM submit RPC and live gestures remain unverified. Marker scan is empty.

### Profile shared-history request identity — 2026-10-02

- A28 `9cdc6b0` adds per-request authority independently of the selected filter. Tab change invalidates it before cancellation;
  every success/error/cancellation path consumes only its own ID before touching the task or UI. Existing account/client/tab checks,
  pagination cursor, deduplication, gallery retry and query semantics remain intact. No network cancellation guarantee is assumed.
- Reference: pinned `PeerInfoVisualMediaPaneNode.swift`, current 1726/1792 and pre-Liquid 1660/1725, scopes and replaces history
  subscriptions; TDLib `022d6020` `SearchChatMessages` topic/filter/from-message contracts checked directly. No Telegram infrastructure copied.
- Three Swift files formatted together; primary warning-free wrapper build
  `.build/logs/xcodebuild/build-Debug-20261002-172655-9917-30165.log` (10s). Audit Simulator PID `10397`:
  `-ui-probe-profile-history-request` passes production token helper checks for A→B→A late success/error/cancel, busy replacement,
  current exactly-once completion, invalidation and retry. Results plus A27/A16/A17/A30b1/A30a regressions are under
  `.build/ui-probe-evidence/astra-a28-primary`. The controller's success/catch/reset wiring is source-reviewed; the probe does not
  construct a real profile, delay a TDLib RPC or exercise tab gestures. No real account/profile/message changes.

### Terminal navigation-plan acceptance — 2026-10-02

- A30b2 prerequisite worker `1584f4d` integrated as `1f47005`. Preparation owns no transferred files; the coordinator rechecks
  ready/source generation, controller preflight, exact stack and transition/modal barriers before a one-shot synchronous commit.
  An accepted replacement is installed without a later rejection that could strand transferred composer files. Production commit
  constructors must not navigate or replace the client. Main is still the only opted-in production entry; Chat activation remains open.
- A bounded identity-snapshot pass visits each original eligible entry once, skips a deferred entry and preserves other routes.
  Changed readiness during a commit schedules one weak coalesced retry. Source/readiness/account changes before acceptance do not
  transfer ownership. This reworks the existing A30a transaction, with the same pinned ChatList/ChatInterfaceState references.
- Three Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-172957-13872-9541.log` (8s); worker log copied with `worker-A30b2-plan-` prefix.
  Audit Simulator PID `14747`: expanded `-ui-probe-client-restoration` passes real coordinator/prepared-plan and isolated lifetime/file
  checks, two entries in one Ready, deferred-first skip, preflight changes, refused commit, terminal install and duplicate/reentrant
  readiness. A30b1/A28/A27/A16/A17 regressions pass beside it in `.build/ui-probe-evidence/astra-a30b2-plan-primary`.
- Actual Main regression: own query `111222` on groups → HOME → app icon, same PID and query; `7` typed without tap produces
  `1112227`. Visually inspected `search-restored-typing.png` records focus/cursor and selected folder; keyboard stayed hidden.
  Own query cleared with Close. No folder/message/account writes. This validates Main after the transaction change, not Chat recovery.

### Poll submission attempt ownership — 2026-10-02

- A31 `b7de6ee` gives each accepted vote attempt an immutable token. The queued RPC checks that token and current route before
  sending; failure and deadline callbacks may clear only their own attempt. A stale callback neither cancels the replacement
  deadline nor publishes a misleading idle state. Authoritative selection changes invalidate old attempts; retry keeps local choices.
- Reference: pinned pre-Liquid `submodules/TelegramUI/Sources/ChatController.swift:3422–3430` owns per-message poll requests;
  `ChatMessagePollBubbleContentNode` reflects current in-progress selections. TDLib `022d6020` `SetPollAnswer` uses message/chat
  identity and zero-based option IDs. No Telegram infrastructure copied or network cancellation guarantee assumed.
- Three Swift files formatted together; warning-free primary build
  `.build/logs/xcodebuild/build-Debug-20261002-174113-33012-16805.log` (10s). The preceding sandboxed attempt could not connect to
  CoreSimulator; the same wrapper succeeded with host access, without changing or resetting a Simulator.
- Audit Simulator PID `36667`, `-ui-probe-poll-submission`: actual store, registered deadline and already-running deadline callback
  tests pass for timeout/retry/late failure, A→B→A authoritative reset, exact replacement timer ownership, no stale notifications,
  pending-choice preservation and duplicate completion. A28/A30b1/terminal-navigation regression probes also pass in
  `.build/ui-probe-evidence/astra-a31-primary`. ChatVM wiring is source-reviewed; no real vote or delayed server RPC was performed.

### Video-note navigation finalization and join — 2026-10-02

- A15a worker `64c47dc` integrated as `bafdde8`: navigation registers an exact account/chat/topic barrier synchronously, freezes
  capture input and joins the sole manual/automatic finish owner. A UI-independent finalizer owns native output → canonical
  recording adopt/append; ChatVM waits before reading drafts. Existing draft/reply/topic/revision survives failed append.
  Explicit Cancel remains destructive; Cancel/state callbacks from a detached preserved recorder cannot reclaim the restored draft.
- Capture state carries its original generation; old callbacks cannot revive dismissed UI. Native terminal failure settles the
  join. The fixture originally named navigation-then-background actually injected capture failure; A15b1 below corrects that name
  and separately tests background preservation. This historical slice alone did not preserve the new segment on background.
  No changes to `InputMessageVideoNote`, send/outcome manifests or TDLib delivery matching.
- References: pinned current `VideoMessageCameraScreen.swift:457–483` waits for stop result; current/pre-Liquid Legacy capture
  output handoff at 1109–1116/1113–1120 and interruption completion at 1349–1356/1353–1360. ChatController foreground handling
  at current 6857–6872/pre 5963–5978 calls `stopMediaRecorder`; `Chat/ChatControllerMediaRecording.swift` 460–480/470–487 selects
  preview for active audio/video. Legacy's separate background observer at 190–198 dismisses. Source does not establish callback
  ordering or universal deletion; on-disk/process-death recovery is a separate BetterTG durability policy.
- Primary first build `.build/logs/xcodebuild/build-Debug-20261002-174405-45697-8734.log` passed without warnings (25s).
  Initial runtime failed before its first finish gate: `recordingUnavailable`, then timeout. Diagnostics `843fde6`/`3e49c9d`
  bounded the failure and exposed ownership. Fixture correction `d34eeb3` (worker `4a224e7`) loads the real recorder view before
  installing capture, matching production `beginCapture`; its gate also reports an early terminal result instead of hanging.
  The exact prior cancellation cause is unproved. No production workaround was added to make the fixture pass.
- Final primary build `.build/logs/xcodebuild/build-Debug-20261002-180134-71658-8387.log` passes without warnings (9s).
  Audit Simulator PID `72550`, `-media-probe-video-note-preservation`: all eight actual-recorder/native-H264-AAC/store cases pass
  for manual/auto ownership before/after finish, pending append, stale-revision failure, explicit Cancel, route isolation and later
  capture failure (original output called it background termination). Evidence: `.build/ui-probe-evidence/astra-a15a-primary`;
  initial timeout/sample and the original output are retained there.
  No user store, real recording, camera permission or server send was touched. Physical capture, rapid-navigation gestures,
  suspension grace time and process death remain unverified.

### Chat restoration history/import foundation — 2026-10-02

- A30b2 worker `760f8cc` integrated as `6aa7ce4`. Detached display values preserve raw source IDs, album members, presentation
  metadata and pagination cursor without mutable wrappers or in-flight mutation flags. Reconciliation rebuilds albums by source ID.
  A separate raw latest cursor bridges toward the seed; it does not jump directly to the old history cursor.
- At most four reads run per batch, with visible seed IDs first. Source/generation and per-message revision checks bracket metadata
  hydration and delivery; permanent deletion tombstones prevent resurrection. Partial reactions/pins do not establish that a stale
  body is current: invalidated reads stay unresolved for explicit retry. Full accepted messages satisfy superseded reads. Latest-page
  tokens reject stale/replayed/reentrant delivery. Errors never auto-poll or imply deletion.
- Exact missing result verified in pinned TDLib `022d6020`: `Requests.cpp:592–607` → `Td.cpp:1392–1407` yields 404 `Not Found`.
  Other errors retain a retryable seed. Import tokens allow one local completion into a retained same-account route before retirement;
  removed/cross-account/retired owners reject it. None authorizes a send on an obsolete client.
- Four Swift files formatted together in the worker; primary combined build
  `.build/logs/xcodebuild/build-Debug-20261002-175112-65343-2137.log` passes without warnings (11s).
  PID `66007`, `-ui-probe-chat-restoration-state` passes value/album/cursor, import and suspended read/hydration/token checks with
  zero server reads/sends. Repeated at `d34eeb3`, PID `72550`. Evidence: `.build/ui-probe-evidence/astra-a30b2-state-primary` and
  `astra-a23a-primary`; worker README/log copied separately. Existing pinned ChatInterfaceState references apply.
  Chat navigation is still disabled; live history, file-import controllers, anchor/focus and shared same-epoch update ordering need wiring.

### Root/list account and client authority — 2026-10-02

- A23a `e1d295e` routes typed RootVM list/chat/user/unread/settings updates through accepted source checks at main delivery.
  Folder unread uses the event's client ID. List reads capture one client for every nested chat/user/group/folder RPC and check
  account/client plus root ownership epoch before publication. Full folder loads and per-chat refreshes also have request IDs;
  a detached folder cannot receive a pending append. Durable document outcome/delete handlers are unchanged.
- Legacy void auth notifications only wake a current-state read; they no longer blindly set the new account's logged-in flag.
  This does not migrate every authorization/topic subscriber or solve all same-client field-update races.
- Reference: current/pre `ChatListUI/Sources/Node/ChatListNode.swift` retains AccountContext at 1216/1213 and 1397/1391;
  current history subscription at 1934 uses that account. TDLib `getChats/getChat/getUser/getSupergroup/getBasicGroup/getChatFolder`
  and existing generated scoped update transport remain unchanged. No Telegram infrastructure copied.
- Five Swift files formatted together; primary warning-free build
  `.build/logs/xcodebuild/build-Debug-20261002-180056-69882-3475.log` (9s), after correcting a missing Foundation import.
  Integrated `d34eeb3`, PID `72550`: `-ui-probe-root-list-authority` passes actual ticket/scoped-delivery checks for delayed
  A→B, replacement client, unscoped event, A→B→A request epoch and mismatched owner. Five A30b2/A31/A29/A30a/A30b1 regression
  results pass in `.build/ui-probe-evidence/astra-a23a-primary`. Real RootVM/RPC wiring is source-reviewed; no real account switch,
  delayed server response or account/list mutation was performed.

### Chat update delivery and integrated regression — 2026-10-02

- A23b `df9eb7a` (worker `6c43e20`) binds 20 ChatVM typed subscriptions to their accepted account/client and exact chat/topic.
  Five asynchronous new/sent/failed/message/reference hydration paths recheck that authority and the nonretired owner before
  publication. Durable send outcomes, deletion transport and local recording-store notifications retain their existing ownership.
  Same-client body/partial/delete ordering and actual Chat foreground restoration remain separate work.
- Reference: the pinned current/pre Telegram AccountContext ownership and A13 accepted-update contract above; generated TDLib
  update models, `getMessage` and captured-client metadata reads are unchanged. No server mutations or account switches exercised.
- Four changed Swift files formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-180630-74419-20491.log`
  passes without warnings (9s). On the audit Simulator, installed `df9eb7a`, PID `75292`, actual generated dispatcher and observer
  probe passes queued A1→A2, A→B→A3, colliding IDs, missing origin, retired owner, route/topic and late callback checks.
  This is an isolated observer test, not delayed live ChatVM/TDLib network proof.
- The same launch passes Root authority, A16 video submission ownership, A13 update source, A12 draft outcomes, A30b2 history/import
  and A31 poll attempt probes. Separate `d34eeb3`, PID `73141`, passes A17 native video-finish regression.
  Evidence: `.build/ui-probe-evidence/astra-a23b-primary` and `astra-a15a-primary/video-note-finish-probe.txt`.
- Production Root/Main smoke on `df9eb7a`: selected `groups`, entered own query `232323`, Home→app icon, observed the same query
  and selected folder, then typed `7` without another focus tap; AX and screenshot show `2323237`. Closed search and verified the
  empty placeholder. Screenshot: `astra-a23b-primary/root-search-foreground.png`. Software keyboard was hidden; text focus was
  demonstrated by input, not by keyboard pixels. This does not prove restoration of an open Chat or a real account switch.

### Animated file transport authority — 2026-10-02

- A05a `128ada2`: all three TGS/WebP/FFmpeg views use one configured request with captured account/client/file identity.
  Scoped notifications check the accepted origin at main delivery; download/cancel closures retain the original client.
  Client replacement retires the request and view. Asset/frame callbacks check request identity, current source and path;
  canceled same-file reuse cannot install an old decode. Thumbnails use the existing explicit-account/client loader.
  Complete files issue no teardown cancellation. Native worker ownership, alpha, caches and timing remain unchanged.
- This is deliberately partial: callers still capture the active client at configure. An old asynchronous consumer can pass an old
  File into a new configure; the next slice makes originating clients explicit through custom emoji, timeline, picker and gallery.
  Shared visible/prefetch download demand (A06) is not implemented by this request wrapper.
- Reference: pinned pre-Liquid `AnimatedStickerNode/Sources/AnimatedStickerNode.swift:288–291,348–424` owns its source subscription,
  disposes/replaces it and gates playback by visibility. TDLib pinned `downloadFile` documents immediate non-synchronous state plus
  `updateFile`; `cancelDownloadFile(onlyIfPending:true)` only cancels a pending request. No Telegram infrastructure imported.
- Six Swift files formatted together. Final build `.build/logs/xcodebuild/build-Debug-20261002-182359-89980-13950.log` passes without
  warnings (11s), after correcting unused-result and weak-reference diagnostics. Simulator PID `91050`, built from this exact source,
  passes `-media-probe-animation-authority`: isolated actual request/notification path, colliding/foreign/unscoped/wrong-file updates,
  queued account replacement, same-file reuse, late RPC, captured cancel and deinit cleanup. Backend closures are fixtures; no TD calls.
  A07 native worker regression and A23 Chat/Root probes also pass in `.build/ui-probe-evidence/astra-a05a-primary`.
  This does not prove real sticker playback, account switching, or all consumer origins.

### Video lifecycle preservation and animated consumer origins — 2026-10-02

- A15b1 `8b42052` (worker `2b45d35`): background/camera/audio interruptions join the immutable capture finalizer, stop input and
  preserve the canonical recording. A per-capture background lease ends once; expiration cancels only a matching unadopted writer,
  never an accepted store save. Repeated events cannot renew the lease. Foreground restores only the retained route/generation to
  paused preview; it cannot restart capture/playback or revive a navigation-detached owner. Initial background state is respected.
- Review caught `.sending` being set before asynchronous export. The fix checks lifecycle epoch immediately before `onSubmit`,
  removes only its own export/thumbnail and retains the recording; an already invoked `onSubmit` is not canceled. Explicit Cancel
  remains destructive. References are the pinned current/pre ChatController→stopMediaRecorder→preview paths in A15a above.
- Four Swift files formatted together; integrated build `.build/logs/xcodebuild/build-Debug-20261002-182819-4794-15394.log` passes
  without warnings (10s). Exact product `8b42052`: PID `6152` lifecycle probe passes 11 recorder/native-writer/private-store scenarios,
  pending preparation, background→foreground during real export, accepted suspended submit, immediate expiry and canonical cleanup.
  Separate launches pass A15a navigation (`7592`), A17 native finish (`19855`), A16 submit ownership (`23359`). Evidence:
  `.build/ui-probe-evidence/astra-a15b1-primary`; worker source/build notes in `astra-a15b1-worker`.
  Lifecycle inputs/background backend are injected; no user stores/sends, hardware capture, real OS suspension/expiration,
  audio-notification delivery or process-death recovery were tested. Voice background/intent ownership remains A15b2.
- A05b `6e5b287` requires an explicit originating client in AnimatedFileView, custom emoji, timeline text/reactions/dice,
  composer stickers, topic icons and gallery cells. The dynamic repository overload is removed. Gallery's existing video owner
  remains usable without reconstructing a client; a new animation cannot fall back to global `td`. Reuse clears thumbnail pixels.
  Fifteen Swift files formatted together; build `.build/logs/xcodebuild/build-Debug-20261002-183343-25876-8180.log` passes without
  warnings (15s). PID `31000` passes animation-authority, native A07 and PiP-context regressions in `astra-a05b-primary`.
  Independent read-only A05a/A05b delta review found no new blocker. Actual multi-account animation/view-decode races, shared demand
  and nonanimated/static-image client plumbing remain outside this bounded proof.

### Shared production history revisions — 2026-10-02

- A30b2 phase 1 `da59789` (worker `4c9142a`) wires the history ledger into ordinary ChatVM and the optional seeded constructor.
  Complete accepted messages install their body before metadata awaits; one four-message lane hydrates metadata. Partial updates,
  permanent deletion and source retirement invalidate older reads. Reaction/pin owners retain their wrapper until both settle.
  Normal pagination checks the same token at synchronous merge. Prepared windows carry only fetched values and an unconsumed token;
  actual installation rechecks revisions and merges current messages, preserving intervening updates instead of overwriting them.
- Restored latest history advances on raw pages, then filters exact topic for rendering. Ready/manual retry is event-driven,
  including one deferred event during batch/latest RPC; a plain failure never loops. Confirmed missing history removes display state
  only; durable recording/send outcomes and file cleanup still require their accepted TD updates. No storage schema changes.
- References: pinned ChatInterfaceState/history restoration and exact TDLib `getMessage` 404 path recorded above; captured-client
  `getMessage/getChatHistory/getMessageThreadHistory` and generated update models. Source review caught prepared-window admission
  before its actual install and sender updates missing a bare message; both were corrected before integration.
- Four Swift files formatted together; primary build `.build/logs/xcodebuild/build-Debug-20261002-183613-37316-13873.log` passes
  without warnings (33s). `da59789`, PID `41056`, `-ui-probe-chat-restoration-state` passes actual ledger/cursor cases: live body,
  partial-before-body/during-hydration, deletion, shared page token, overlapping mutation owners, deferred Ready/error/cancel and
  foreign-topic raw bridge. A23 Chat/Root, A31 poll and animation-authority regressions pass in
  `.build/ui-probe-evidence/astra-a30b2-production-primary`. Worker notes/logs are preserved separately.
- Probe read/hydration closures are isolated: actual ChatVM constructor, ordinary timeline and delayed TDLib transport still need
  production smoke. ChatView restoration is not enabled; the controller must transfer a quiescent composer/history, settle its
  one-shot pixel anchor, then start freshness. Raw unresolved reply/forward dependencies, A22 scroll interaction epochs and other
  secondary-route restoration remain open. This phase is production wiring, not a complete A30 claim.

### A06 animated-file demand — 2026-10-02

- `09fa140` replaces per-view transport cancellation with `AnimatedFileDemand`, keyed by originating account UUID, client ID and
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
  `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro / iOS 26.5, installed source `09fa140`, PID `60930`:
  `-media-probe-animation-demand`, `-media-probe-animation-authority` and `-ui-probe-chat-restoration-state` all pass. Results:
  `.build/ui-probe-evidence/astra-a06-primary`. Parent and independent delta reviews completed, including the terminal-race repair.
- Demand tests run actual production pool/request code with isolated suspended transport and notifications: duplicate visible
  owners, deinit, cancelled prefetch, pending start reuse, delayed cancel/reacquire, queued completion/failure, stale initial reply,
  client replacement, pre-start cancellation, completed cache and explicit retry. No server calls or user stores. Actual three-view
  decode callbacks/TDLib scheduler, nonanimated downloads and cross-arbitration with VOD ranges are not established by these probes.

### A30b2 quiescent Chat controller — 2026-10-02

- `494bf56` (worker `7f98a52`) enables the existing terminal navigation replacement for ordinary Chat. Captured target-client
  metadata, account/chat/topic and retained-route checks precede synchronous composer/history ownership transfer. Imports, marked
  text, modal/context menus, gestures, capture/send operations and timeline transitions defer replacement. Paste/Photos/camera/files
  register import ownership before asynchronous work; same-account results can finish on a retained old-client route.
- Selection, focus and mic/video mode transfer separately. The retired text view resigns only its own responder; the new controller
  restores one message ID + pixel offset after snapshot, appearance, layout and keyboard settlement, then starts history freshness.
  User scroll/input invalidates this initial anchor. A22 general timeline epochs and active capture restoration are not repaired here.
- Primary follow-up `9495f0a` adds the missing explicit retry after emoji-picker Done or invalid-context dismissal. UIKit's
  interactive presentation delegate does not cover that programmatic completion. Foundation probe labels now state that those
  probes do not exercise controller navigation. A DEBUG-only, content-free log identifies actual viewport settlement.
- References: pinned current `ChatInterfaceState/Sources/ChatInterfaceState.swift` 232–270 and pre-Liquid 514–531, distinct
  compose/reply/edit/history/media state and message-index-relative offset. TDLib captured-client `getChat/getForumTopic/getMessage`,
  chat/thread history and accepted ready/update source; no new server mutation or storage schema.
- Primary builds: `.build/logs/xcodebuild/build-Debug-20261002-190318-62891-1540.log` (12s), combined voice build
  `build-Debug-20261002-190401-63298-26208.log` (11s), final picker fix `build-Debug-20261002-192208-71024-31859.log` (7s), all
  zero warnings after each slice's single SwiftFormat invocation. Sandbox-only CoreSimulator access failed; authorized wrapper retry
  succeeded without resetting data. Source review also corrected first-responder retirement before integration.
- Audit Simulator `59EB535C-3610-41A2-AB68-53A9467DC24B`, iPhone 17 Pro / iOS 26.5: source `fe5de21`, PID `64668`, actual
  Saved Messages retained latest and settled non-latest viewport plus empty-composer caret after Home→foreground. The initial
  non-latest screenshot preceded deceleration and is not anchor proof; the repeated settled pair is visually consistent, without an
  automated pixel-error measurement. Software keyboard was hidden by the hardware-keyboard setup.
- At `9495f0a`, PID `71481`, open emoji-picker survived Home→foreground; Done returned the actual chat. At 19:26:46 the same
  process logged `Chat client restoration: viewport settled; fresh history starts`. No emoji selection, text input, attachment,
  send or account switch. Screenshots and state probe: `.build/ui-probe-evidence/astra-a30b2-controller-primary`; worker notes are
  separate. Chat state/composer foundation and A06 authority/demand probes pass; their isolated transports are not network proof.
- Pending: interrupted real provider imports, nonempty edit/reply/attachment transfer, software-keyboard transitions, active voice/video,
  ForumTopics/Archive/editors, live account switches and delayed server-history races. Full A30 remains partial.

### A15b2 voice lifecycle checkpoint — 2026-10-02

- `15871f5` (worker `f12e3d1`) separates interaction, background and audio-interruption suspension. Clearing one reason cannot
  revive another or an older permission/trim/resume/preview/send intent. Background pauses preview and checkpoints the canonical
  PCM/trim/promotion owner. One bounded UIKit time assertion is exact-once, including immediate expiration; expiration does not
  cancel canonical persistence. Foreground does not resume capture, playback or sending automatically.
- `fe5de21` (worker `0251285`) fixes a primary-review finding: background must not wait on upload-action/reply-validation network
  preflight. The checkpoint marker ends when encoded canonical media is durable, before network awaits. A task captured while still
  encoding sees its invalidated send epoch and retains the draft. Accepted RPCs still register their actual temporary ID and retain
  their files. Fallback closed-segment promotion now keeps the route barrier through CPU/store completion. Storage formats unchanged.
- References: pinned current/pre `TelegramUI/Sources/ChatController.swift` 6857–6872 / 5963–5978;
  `Chat/ChatControllerMediaRecording.swift` 460–480 / 470–487 (stop into preview);
  `ManagedAudioRecorder.swift` 448–455 and 522–560 (session deactivation and Ogg pause/resume). Durable disk policy is BetterTG's
  adaptation; source does not establish Telegram observer ordering or identical process-death behavior. TDLib send/reply preflight
  and returned message-ID registration retain the earlier A12/A14 contracts.
- Four worker Swift files and combined nine-file primary set formatted before their builds. Primary combined build
  `.build/logs/xcodebuild/build-Debug-20261002-190401-63298-26208.log`: PASS 11s, zero warnings; follow-up build above also clean.
  On the audit Simulator, sources `fe5de21` / `9495f0a`, PIDs `64668` / `71481`, `-media-probe-voice-lifecycle` and
  `-media-probe-voice-finalization` pass. Proof: `.build/ui-probe-evidence/astra-a15b2-primary`; worker notes/logs retained separately.
- Native isolated proof uses real PCM16/48kHz trim/concatenate, Ogg codec and private recording/send stores: independent reasons,
  route barrier, duplicate/expired assertion, stale intent, failed append, explicit discard, metadata and accepted-ID ownership.
  It neither instantiates a real ChatVM nor emits OS audio notifications/server RPCs. Real microphone/interruption/process suspension,
  ChatVM's suspended network preflight and actual accepted send remain unverified; this does not close those runtime gaps.

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

- Active continuous work resumed explicitly after `8268947`; no further resume is required. A01/A02/A03/A07 have bounded
  warning-free build/probe proof; `909215a` repairs A11 with production navigation/relaunch/Delete proof. A13 `c356513` has
  accepted-event transport proof; A04 through `ef8f4ba` has native and Simulator decoder/controller proof. A12 `847b838` and
  A18 `76f9998` have combined isolated store/stream proofs. A14 `bb01b8f` and A19 `d8ed16e` have integrated bounded probes.
  A24 `b18da97` has integrated edit-policy proof; A26 `8519b33`/`5a87726` has store and own voice reinstall/discard proof.
  A29 `15f146f` has isolated mutation-authority proof and read-only cold-launch folder/editor navigation smoke.
  A27 `b0db39f` has integrated effective-permission/authorization proof.
  A30a `0820359`/`c5d3f8b` has production same-PID root-list/search restoration proof; A17 `e8a0eb1` has native finish-owner proof.
  A30b1 `ef558ec` has isolated one-shot transfer proof; A16 `a72d93b` has actual recorder/store handoff proof.
  A28 `9cdc6b0` has pagination registration proof; real delayed profile RPC remains unverified.
  A31 `b7de6ee` has poll-attempt/deadline ownership proof; no server votes or delayed live RPC proof.
  A15a navigation joins pass through `d34eeb3`; A30b2 history/import helpers `6aa7ce4` and Root A23a `e1d295e` pass bounded probes.
  A05a/b and A15b1 have bounded source/transport/native proofs; shared production history revisions pass at `da59789`.
  A06 shared animated demand has bounded transport proof at `09fa140`; A15b2 voice lifecycle passes at `fe5de21`.
  Quiescent Chat A30b2 is active at `494bf56`/`9495f0a` with bounded actual-chat smoke. Secondary routes, remaining A23,
  text A10/A25 and other queued findings remain open.
  Broad parity is not complete.
  B01 still blocks the original Simulator database; the separate audit Simulator is now logged in and usable without data reset.
- Latest verified code: `9495f0a`, adding quiescent Chat controller restoration and voice lifecycle to the A06 baseline. Chat state,
  composer foundation and voice lifecycle/finalization probes pass (PID `71481`); A06 demand/source also pass on combined `fe5de21`.
  Actual Chat modal/background/Done restoration passes; earlier Root/poll proofs remain at `da59789` and Main search/focus at `df9eb7a`.
  Warning-free build: `.build/logs/xcodebuild/build-Debug-20261002-192208-71024-31859.log`.
  Production/dependency scan over `project.yml`, `BetterTG`,
  `BetterTGNotificationService` and `Packages` has no VLC, SwiftUI/hosting/representable or Liquid Glass markers.
  The prompt/document delta received an independent read-only review. Neither clean build nor this marker scan closes the audit.
- The protected auxiliary `astra-animation-worker/BetterTG` worktree produced integrated A04/A18/A19/A26/A30a/A30b1/terminal plans;
  A30b2 controller/history and A23b Chat update-delivery fences are integrated; its A10 text-spoiler worker result awaits integration.
  Native before/after fixtures and logs were preserved in `.build/ui-probe-evidence/astra-a04-*`.
  `astra-outcome-source/BetterTG` produced integrated A13/A12/A14/A24/A29/A27/A17/A16/A15a/A15b1/A15b2; its A08 timing result awaits integration.
  Parent owns idb; Simulators remain booted.
  Do not force-delete protected worktrees. Historical A07 worker proofs remain in the primary checkout.
- Initial documentation-only validation at `6b417da`: `./build.sh build` passed without warnings on Xcode 26.6; log
  `.build/logs/xcodebuild/build-Debug-20261002-141016-42207-16861.log`. The missing ignored `Secret.swift` was restored from the
  main checkout for the build and is excluded from the commit. Documentation-only peer review passed; no Swift source edits or
  new runtime smoke were performed. This build does not close any implementation-audit row.
- Exact next slices: integrate A08 native timing and A10 text spoilers, run their actual native/UIKit probes and affected regressions;
  then A09 inline Apple-container animation and A20 media concealment. Retain Chat's untested nonempty composer/import/keyboard cases.
  Telegram's chat-level background path stops into preview; Legacy also has a separate dismiss observer. Their ordering and durable
  process-death preservation are not established by static source. Preserve the bounded A15a proof and its failed initial fixture evidence.
  The full A30 transaction
  spans too many ownership boundaries for one bounded slice. Continue A05–A10/A15 and A20–A23/A25/A32.
  Own A26 draft recovery/reinstall/discard is complete; keep its backups, do not restore it again.
  A12 crash before registration retains unresolved ownership; do not guess an outcome. Retain A04's cold partial-range/lookahead proof gap.
  B01 needs a data-preserving TDLib investigation. Continue owner/PiP, complete MessageContent/actions, composer/timeline,
  profile/gallery and account/list/shell audit
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
