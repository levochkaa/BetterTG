# Astra audit baseline and coverage

- Date/source: 2026-10-02, clean `1eb08fff72488cd9de768a37ef1844b96ee5b495`. Pre-UIKit base is
  `d27567e3513b2be527b21a2409b022d592db75a6` (parent of `6ce23cb`); VLC replacement began at `c843ef5`, parent
  `534f8a374aa60014210779eaed1397a5d2f2085c`. Audit current reachable code and the accumulated history, including integration
  merge `37fb759`; other branches and unrelated push/build work are not authorization to merge or rewrite them.
- Official references: `telegram-upstream/master` = `6ad963e5b62d354da79040f388ae2b9132fb17b8`; classic baseline remains
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`. TDLibKit is pinned to `1.5.2-tdlib-1.8.66-022d6020`, TDLib `022d6020`;
  Lottie 4.6.1, libwebp 1.6.0 and checksum-pinned FFmpeg 9.0 are unchanged.
- Current marker scan over `project.yml`, `BetterTG`, `BetterTGNotificationService` and `Packages` found no VLC API/dependency,
  SwiftUI/hosting/representable or Liquid Glass production marker. This is a dependency/source check, not visual/runtime parity.

| Area | Production entry points and shared dependencies located | Initial source pass; later fixes and proofs are recorded below |
| --- | --- | --- |
| Animated media | `MessageContentView`, `MessageTextView`, reactions, composer picker and gallery → `AnimatedFileView`, TGS/WebP/FFmpeg views, `CustomEmojiStickerRepository` | Source pass through these consumers; A07 worker lifecycle/reuse probe passed, other runtime coverage and fixes outstanding |
| Voice/video notes | `ChatBottomArea`, `VideoNoteRecorderViewController`, `ChatVM` → capture/writer/codec, recording/send stores and coordinators, message playback | Voice source pass at `edf7f3a`: recording/trim/PCM/codec, preview, send/retry/relaunch/outcomes and destination ownership; A11–A14. Independent video source pass at `7f4f26d` confirms shared A12/A13 plus A15–A17; camera/interruption/server behavior remains unproved |
| VOD | `ChatView`/`ChatViewAlbum` → `GalleryVideoPlaybackOwner`, `LocalMediaPlayer` or FFmpeg sample player → range coordinator/resource loader/decoder/renderer/C AVIO | Source pass over range/loader and C/Swift decoder/render session; primary owner/PiP account/restoration pass at `7633731` finds A18/A19; other lifecycle and active-system proof pending |
| Content/actions | `MessageContentPresentation`, `MessageMetadataPresentation`, structured/text/reaction views → `ChatVM`, `MessageForwardingService`, topic/forward controllers | Source pass at `af9349c`: pinned 104-case classifier, production cell/media dispatch and spoiler/secret guards; A10/A20/A21. Structured actions at `02f9331` find A31; exhaustive live content/action behavior remains unverified |
| Composer/timeline | `ChatBottomArea`, `ChatView`, `ChatVM`, `ChatDraftKey`, `MessageSendTransition`, date/topic header models | Timeline source pass at `cce4c51`: raw cursor, album/header identity, anchors and prefetch; A22. Composer pass at `878eafb`: edit dispatch/completion, semantic formatting, snapshot lifetime, ID aliases and forward isolation; A24/A25 and transition proof gaps |
| Profiles/gallery | Peer profile/control/avatar controllers → `ChatViewAlbum` gallery and owner/export/actions | Source pass at `1fd5c61`: roles, member/admin/tag controls, edit, avatar history/video, pagination, transition identity/cleanup, gesture arbitration and rotation; A27/A28. A19 isolated context/owner probes pass; active system PiP and real server actions remain unverified |
| Accounts | `TDLib`, `TelegramAccountRegistry`, root/settings/login controllers → client activation/retirement, storage, update subjects | Initial source pass at `02f9331`: UUID databases, atomic registry, client retirement, auth routing and background ownership; A23/A30. No real add/switch/logout or notification-service handoff proof |
| Lists/shell | `MainView`, `RootVM`, `FolderView`, `ChatFolderManagementViewController`, navigation/context-menu views | Initial source pass at `02f9331`: frozen list payloads versus dynamic action clients A29, page/tab state and full-width safe-area constraints. Secondary surfaces/search mutations and visual matrix remain partial |
