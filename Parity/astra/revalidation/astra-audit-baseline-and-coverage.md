# Astra audit baseline and coverage

- Date/source: 2026-10-02, clean `0727fc8244e0cfd812e4572e0d0ae8d0fcfac278`. Pre-UIKit base is
  `67ecc4ff2287483652019b40f383d50015a35a77` (parent of `a543a0d`); VLC replacement began at `6216eee`, parent
  `0599bfdc8ff862a548b686b0f04df8b2f8ec28e5`. Audit current reachable code and the accumulated history, including integration
  merge `5d990c1`; other branches and unrelated push/build work are not authorization to merge or rewrite them.
- Official references: `telegram-upstream/master` = `6ad963e5b62d354da79040f388ae2b9132fb17b8`; classic baseline remains
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`. TDLibKit is pinned to `1.5.2-tdlib-1.8.66-022d6020`, TDLib `022d6020`;
  Lottie 4.6.1, libwebp 1.6.0 and checksum-pinned FFmpeg 9.0 are unchanged.
- Current marker scan over `project.yml`, `BetterTG`, `BetterTGNotificationService` and `Packages` found no VLC API/dependency,
  SwiftUI/hosting/representable or Liquid Glass production marker. This is a dependency/source check, not visual/runtime parity.

| Area | Production entry points and shared dependencies located | Initial source pass; later fixes and proofs are recorded below |
| --- | --- | --- |
| Animated media | `MessageContentView`, `MessageTextView`, reactions, composer picker and gallery → `AnimatedFileView`, TGS/WebP/FFmpeg views, `CustomEmojiStickerRepository` | Source pass through these consumers; A07 worker lifecycle/reuse probe passed, other runtime coverage and fixes outstanding |
| Voice/video notes | `ChatBottomArea`, `VideoNoteRecorderViewController`, `ChatVM` → capture/writer/codec, recording/send stores and coordinators, message playback | Voice source pass at `ad25f97`: recording/trim/PCM/codec, preview, send/retry/relaunch/outcomes and destination ownership; A11–A14. Independent video source pass at `ddb6764` confirms shared A12/A13 plus A15–A17; camera/interruption/server behavior remains unproved |
| VOD | `ChatView`/`ChatViewAlbum` → `GalleryVideoPlaybackOwner`, `LocalMediaPlayer` or FFmpeg sample player → range coordinator/resource loader/decoder/renderer/C AVIO | Source pass over range/loader and C/Swift decoder/render session; primary owner/PiP account/restoration pass at `424154a` finds A18/A19; other lifecycle and active-system proof pending |
| Content/actions | `MessageContentPresentation`, `MessageMetadataPresentation`, structured/text/reaction views → `ChatVM`, `MessageForwardingService`, topic/forward controllers | Source pass at `458e2f8`: pinned 104-case classifier, production cell/media dispatch and spoiler/secret guards; A10/A20/A21. Structured actions at `91e75e6` find A31; exhaustive live content/action behavior remains unverified |
| Composer/timeline | `ChatBottomArea`, `ChatView`, `ChatVM`, `ChatDraftKey`, `MessageSendTransition`, date/topic header models | Timeline source pass at `fed651f`: raw cursor, album/header identity, anchors and prefetch; A22. Composer pass at `806b0d2`: edit dispatch/completion, semantic formatting, snapshot lifetime, ID aliases and forward isolation; A24/A25 and transition proof gaps |
| Profiles/gallery | Peer profile/control/avatar controllers → `ChatViewAlbum` gallery and owner/export/actions | Source pass at `8bdf9dc`: roles, member/admin/tag controls, edit, avatar history/video, pagination, transition identity/cleanup, gesture arbitration and rotation; A27/A28. A19 isolated context/owner probes pass; active system PiP and real server actions remain unverified |
| Accounts | `TDLib`, `TelegramAccountRegistry`, root/settings/login controllers → client activation/retirement, storage, update subjects | Initial source pass at `91e75e6`: UUID databases, atomic registry, client retirement, auth routing and background ownership; A23/A30. No real add/switch/logout or notification-service handoff proof |
| Lists/shell | `MainView`, `RootVM`, `FolderView`, `ChatFolderManagementViewController`, navigation/context-menu views | Initial source pass at `91e75e6`: frozen list payloads versus dynamic action clients A29, page/tab state and full-width safe-area constraints. Secondary surfaces/search mutations and visual matrix remain partial |
