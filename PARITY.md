# BetterTG / Telegram iOS Parity

This file is the checkpoint ledger for the UIKit + Combine + TDLibKit implementation. Telegram references use
`telegram-upstream/master` unless a commit is pinned. The classic pre-Liquid baseline is
`8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, the parent of Telegram's first first-parent `Glass` commit.

Status values: **done** has local implementation proof, **partial** is usable with listed gaps, **next** is the next
bounded slice, and **queued** has not started. Gifts, Stars, collectibles, boosts, Premium, ads, livestreaming, and
Telegram infrastructure (Texture, SignalKit, Postbox, Display, ComponentFlow) are intentionally out of scope.

| Priority | Flow | Telegram reference | TDLib API / model | Status and proof |
| --- | --- | --- | --- | --- |
| P0 | Remove MobileVLCKit; local audio/video playback seam | `submodules/TelegramUniversalVideoContent/Sources/PlatformVideoContent.swift` at the pre-Liquid baseline | `downloadFile`, `updateFile`, `cancelDownloadFile` | **partial** — `LocalMediaPlayer` uses AVFoundation, gallery playback pauses offscreen and has thumbnail fallback. `./test.sh` passes and `rg` finds no VLC dependency/import/API marker in `project.yml` or `BetterTG`. FFmpeg fixture coverage is still required for unsupported containers/codecs. |
| P0 | TGS stickers and animated/custom emoji | `AnimatedStickerFrameSource.swift` gzip/rlottie path, `AnimatedStickerNode.swift` lifecycle, and the self-contained Watch `RLottieKit/TgsDecompress.swift` facade | `MessageSticker`, `Sticker`, `File`, `downloadFile`, `updateFile` | **next** — add gzip + Lottie/rlottie decode, looping, shared timing, cache, cancellation, and static fallback. |
| P0 | Animated WebP | `submodules/WebPBinding/Sources/UIImage+WebP.m`; Telegram only uses its static frame fallback | `StickerFormat.webp`, `File`, `downloadFile`, `updateFile` | **queued** — implement the missing `libwebpdemux` frame/timing path, cache, visibility pause, and cancellation; there is no animated Telegram implementation to port. |
| P0 | WebM/VP9 alpha stickers and generic FFmpeg playback | `AnimatedStickerNode/VideoStickerFrameSource.swift`, `FFMpegMediaVideoFrameDecoder.swift`, `FFMpegAVFrame.m` | `StickerFormat.webm`, `File`, `downloadFile`, `updateFile` | **queued** — add FFmpeg YUVA decode/render with alpha preservation, bounded cache, and Apple-media fast path. |
| P0 | Voice notes: Ogg Opus, waveform, record/lock/edit/send | Telegram voice-message recorder/player paths; reference audit pending | `VoiceNote`, `InputMessageVoiceNote`, `downloadFile`, `sendMessage` | **partial** — downloaded playback, waveform display, and seeking exist; recording, lock/cancel, pause/resume, preview, trim, retry, and verified Ogg Opus coverage remain. |
| P0 | Video notes | `submodules/TelegramUI/Components/VideoMessageCameraScreen`, `ResultPreviewView.swift` | `InputMessageVideoNote`, `sendMessage` | **queued** — AVFoundation capture/writer, round preview/playback, camera switching, gesture states, segments, trim, and limits. |
| P0 | VOD before full download, range seek/refetch, PiP | pre-Liquid `ChunkMediaPlayerV2.swift` and `ChunkMediaPlayerDirectFetchSourceImpl.swift` (256 KiB reads, 2 MiB fetches, 10 s lookahead, stale-seek cancellation) | `downloadFile(offset:limit:)`, `getFileDownloadedPrefixSize`, `updateFile`, `cancelDownloadFile` | **queued** — TDLibKit-native byte-range source, lookahead/reuse, retry/offline/cache, inline/fullscreen/PiP. Livestreaming is excluded. |
| P0 | Exhaustive message content and actions | pre-Liquid `submodules/TelegramUI/Sources/ChatMessage*` behavior | `MessageContent`, reply/quote/forward/edit/delete/reactions/pins/topics APIs | **queued** — audit every generated `MessageContent` case and install explicit unknown fallback. |
| P0 | Composer and send/delete transitions | pre-Liquid chat input panel and message transition paths | `FormattedText`, `InputMessageContent`, `sendMessage`, edit/reply APIs | **queued** — one UIKit floating blur island; snapshot flight into anchored insertion; collapse/fade/slide delete. |
| P1 | Profiles, shared media, fullscreen gallery | pre-Liquid peer info/gallery controllers | user/basic-group/supergroup/full-info and message-search APIs | **queued** — exact thumbnail transitions, paging/prefetch, zoom/dismiss gesture arbitration, video controls, actions, and state restoration. |
| P1 | Multiple accounts | Telegram account manager behavior without copying Postbox | separate TDLib clients and databases, authorization state, `logOut` | **queued** — isolated clients/storage/subscriptions plus add/auth/switch/remove/logout. |
| P1 | Chats, folders, archive, search, edit/reorder | pre-Liquid chat list/filter behavior | chat lists/positions/folders, pin/mute/read/delete/clear/draft APIs | **queued**. |
| P1 | Timeline stability and performance | pre-Liquid chat history behavior | `getChatHistory`, `updateNewMessage`, `updateMessageContent`, file updates | **partial** — UIKit collection timeline exists; audit anchor `messageId + pixelOffset`, prepend/resize/keyboard invariants, account scope, prefetch cancellation, and main-thread work. |
| P2 | Classic shell/navigation polish | pre-Liquid navigation/tab bars | n/a | **partial** — UIKit shell exists; audit every surface for full-width safe-area blur and forbidden floating/glass markers. |

## Checkpoint

- Current slice: remove MobileVLCKit from the durable project and replace both runtime consumers with a reusable
  AVFoundation player seam.
- Verification: `./test.sh` passes; exact marker scan and `git diff --check` pass. The implementation and ledger are
  delivered together in one focused commit.
- Next slice: TGS gzip decode and animated sticker lifecycle on top of the existing TDLib file loader.
