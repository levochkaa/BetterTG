# BetterTG / Telegram iOS Parity

This file is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation. Telegram references use
`telegram-upstream/master` unless a commit is pinned. The classic pre-Liquid baseline is
`8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, the parent of Telegram's first first-parent `Glass` commit.

Status values: **done** has local implementation proof, **partial** is usable with listed gaps, **next** is the next
bounded slice, and **queued** has not started. Gifts, Stars, collectibles, boosts, Premium, ads, livestreaming, and
Telegram infrastructure (Texture, SignalKit, Postbox, Display, ComponentFlow) are intentionally out of scope.

| Priority | Flow | Telegram reference | TDLib API / model | Status and proof |
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
| P0 | Composer and send/delete transitions | pre-Liquid chat input panel and message transition paths | `FormattedText`, `InputMessageContent`, `sendMessage`, edit/reply APIs | **partial** — one UIKit floating blur island owns formatted text, photos/camera, reply/edit and voice/video states in ordinary and explicit-topic chats. Sends clear UI only after TDLib acceptance; partial albums retain selection, edits preserve the underlying draft, draft-clear failures retry without erasing newer input, and topic/activity routing is exact. Remaining: emoji/sticker/GIF/files breadth, forward comment/draft, snapshot flights into anchored insertion and collapse/fade/slide delete. |
| P1 | Profiles, shared media, fullscreen gallery | pre-Liquid peer info/gallery controllers | user/basic-group/supergroup/full-info and message-search APIs | **queued** — exact thumbnail transitions, paging/prefetch, zoom/dismiss gesture arbitration, video controls, actions, and state restoration. |
| P1 | Multiple accounts | Telegram account manager behavior without copying Postbox | separate TDLib clients and databases, authorization state, `logOut` | **queued** — isolated clients/storage/subscriptions plus add/auth/switch/remove/logout. |
| P1 | Chats, folders, archive, search, edit/reorder | pre-Liquid `ChatListItem.swift`, chat list/filter controllers | chat lists/positions/folders, pin/mute/read/delete/clear/draft APIs | **partial** — main/archive/custom-folder lists and paging already exist; folder tabs are classic full-width material, and chat cells now use contiguous Telegram geometry with date, delivery, unread/mute/pin state and account-backed actions. Remaining: edit/reorder/include/exclude completeness, clear history/draft parity, archive reveal gestures, richer delivery/typing states and mutation account fencing. |
| P1 | Timeline stability and performance | pre-Liquid/current `ChatMessageItemImpl.swift` and `ChatMessageDateHeader.swift` history/header behavior | `getChatHistory`, `updateNewMessage`, `updateDeleteMessages`, file updates | **partial** — stable message/album/topic/date IDs, raw-history pagination cursor, cross-page album merging, message-only prefetch/read/selection and visible `messageId + pixelOffset` restoration cover structural snapshots. Composer/keyboard insets, object-driven and autonomous cell self-sizing, bulk reconfigure, Dynamic Type and rotation now capture the same anchor or latest edge; mutation depth discards stale deferred anchors and never fights active dragging. Every chat emits one stable localized date row per day with exact date→topic ordering. Remaining proof/gaps: a live pagination/album seam, software-keyboard-attached runtime proof and eliminating residual metadata work from the main actor. |
| P2 | Classic shell/navigation polish | pre-Liquid navigation/tab bars, `ChatListFilterTabContainerNode.swift` and `ChatListItem.swift` | n/a | **implemented classic shell/list breadth** — the bottom folder bar is one edge-to-edge `systemChromeMaterial` surface through the safe area; its scrollable tabs use the pre-Liquid three-point selected line instead of an inset lens/capsule. Context menus use ordinary `systemMaterial` blur and classic corners. Chat-list cards are replaced by contiguous 76pt full-width rows with 60pt avatars at x=10 and separators from x=80. Source search finds no `UIGlassEffect`, `glassEffect` or `cornerConfiguration`. Warning-free build and real-state idb proofs are below. Remaining P2: systematic audit of secondary navigation/search/action surfaces. |

## Checkpoint

- Current slice: base all-messages forums now combine stable date/topic boundaries with General-or-reply text/photo/voice/video routing,
  while the route draft remains `topic:nil` and durable media persists its immutable send topic separately.
- Timeline invariants: raw TDLib pagination owns the cursor; `mediaAlbumId` owns grouped identity across pages; heterogeneous
  message/date/topic items rebuild from canonical state; only messages participate in behavior; every structural apply restores a visible
  message + exact pixel offset. Date→topic ordering and significant-time/locale reconfiguration follow Telegram's header spaces.
- Verification: warning-free Xcode 26.6 build `.build/logs/xcodebuild/build-Debug-20260831-091301-75604-22504.log`; focused reviews are
  clean. PID `71701` passed frozen-destination voice/video recording/send/relaunch probes with no crash/assert; PID `67526` and the date
  smoke stayed alive. Simulator remains booted.
- Proof blocker: current simulator data has no safe reachable forum with `viewAsTopics == false`, so real topic-header tap and live
  General/reply send remain unmutated/unproved. Next slice: retain `messageId + pixelOffset` across keyboard/inset and self-sizing media
  changes, then continue timeline insertion/delete transitions.

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
- Persistent session rollover is complete; sample-buffer PiP remains the independent VOD architecture gap.

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
