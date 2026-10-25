# Gallery Save and secured Share slice

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
