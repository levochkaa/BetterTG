# A09 inline Apple-container animation — 2026-10-02

- `2edc1de` (worker `fb65e3c`) routes native `messageAnimation` through the existing gallery playback owner. Inline and gallery
  transfer the same view/layer/AVPlayerItem with attachment tokens. All visible eligible animations loop silently; ordinary videos
  keep largest-visible-area selection. Offscreen loaded media pauses; pending completed-file demand cancels and retries on visibility.
- Owner construction now requires originating context; file-player configuration requires an explicit range coordinator. Thumbnail
  loading receives captured account/client. Client replacement revokes owners; animation background gates do not reauthorize them.
  Kind/fileID/editDate checks reject stale media owners. Caption-only edit may conservatively restart the same file's item.
- Pinned TDLib `Animation` has no `supportsStreaming`; this slice waits for a completed-file lease and does not claim early MP4
  animation playback. Prefetch uses thumbnails, never source MP4 as an image. Secret/spoiler animations fail closed to static
  minithumbnail pending A20/A21; ordinary-video spoiler remains open. FFmpeg GIF/WebM routes remain distinct.
- References: pinned current/pre `ChatMessageInteractiveMediaNode.swift` 1989–2029 / 1966–2006 and visible attachment
  2166–2175 / 2097–2106; `AccountContext/Sources/UniversalVideoNode.swift` 143–168;
  `TelegramUniversalVideoContent/Sources/UniversalVideoContentManager.swift` 161–235;
  `GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift` 1575 / 1697. No upstream player infrastructure copied.
- Five Swift files formatted together; primary `.build/logs/xcodebuild/build-Debug-20261002-194359-83221-25084.log`: PASS15s,
  zero warnings. Audit Simulator source `2edc1de`, separate launches: inline-animation PID `83851`, gallery-owner PID `84406`,
  PiP-context PID `84924`. All three pass; files in `.build/ui-probe-evidence/astra-a09-primary`, worker notes/logs separate.
- New probe creates private native H.264 media and real production owner/MediaGalleryCell/LocalMediaPlayer: two loop boundaries,
  silent same-item/layer handoff, stale tokens, offscreen pause/resume, pending full-download cancellation/retry and context revocation.
  Range backend/current-source events are isolated. Gallery regression preserves finite ranges/FFmpeg continuity and source factory;
  PiP-context regression preserves stop/restore authority. Active system PiP remains unsupported on this Simulator and unproved.
- No server calls, camera/OS-interruption events, user stores or account switches. Real authenticated MP4-GIF scrolling, transport,
  no-flash gallery gestures and device energy remain unverified. Secret/spoiler reveal, partial-file animation playback and seamless
  caption-only edits are explicitly outside this bounded result.
