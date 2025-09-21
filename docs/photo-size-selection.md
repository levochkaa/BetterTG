# PhotoSizeType Selection Guide

This project maps Telegram thumbnail types from `https://core.telegram.org/api/files#image-thumbnail-types`.

## Size map

| `PhotoSizeType` | TDLib type | Meaning |
|---|---|---|
| `.sBox` | `"s"` | Box thumbnail, up to `100x100` |
| `.mBox` | `"m"` | Box thumbnail, up to `320x320` |
| `.xBox` | `"x"` | Box thumbnail, up to `800x800` |
| `.yBox` | `"y"` | Box thumbnail, up to `1280x1280` |
| `.wBox` | `"w"` | Box thumbnail, up to `2560x2560` |
| `.aCrop` | `"a"` | Cropped thumbnail, up to `160x160` |
| `.bCrop` | `"b"` | Cropped thumbnail, up to `320x320` |
| `.cCrop` | `"c"` | Cropped thumbnail, up to `640x640` |
| `.dCrop` | `"d"` | Cropped thumbnail, up to `1280x1280` |
| `.iString` | `"i"` | Sticker/photo with exact size |
| `.jOutline` | `"j"` | Outline for animated sticker thumbnail |

## Fallback behavior in code

`[PhotoSize].getSize(_:)` now falls back only within the same family:

- Box chain: `w -> y -> x -> m -> s`
- Crop chain: `d -> c -> b -> a`
- `i` and `j`: exact-only (no cross-family fallback)

If no candidate is available, `nil` is returned.

## How to choose a size

- Use `.sBox` for tiny UI thumbnails (`~20-40pt`) such as chat list and reply previews.
- Use `.mBox` for small cards/previews where the image is visible but not a primary element.
- Use `.xBox` for regular media in chat when you want a good quality/performance balance.
- Use `.yBox` for large media or full-screen viewing where higher detail matters.
- Use `.wBox` only when very high detail is required and extra bandwidth is acceptable.
- Use crop types (`.aCrop`...`.dCrop`) only when a cropped thumbnail is explicitly desired.
- Use `.iString`/`.jOutline` for sticker-specific flows.

## Current project choices

- `LastOrDraftMessageView` and `ReplyMessageView`: `.sBox` (small inline previews).
- `MessageContentView` and `ChatViewAlbum`: `.yBox` (larger media display and share flow).
