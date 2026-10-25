// RLottieBridge.h

#ifndef RLOTTIE_BRIDGE_H
#define RLOTTIE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// An rlottie animation, as Telegram-iOS's RLottieInstance holds one. Not thread-safe: render one frame at a time.
typedef struct RLottieBridgeAnimation RLottieBridgeAnimation;

/// Parses Lottie JSON. A non-empty `cacheKey` keeps the parsed model in rlottie's cache, so another animation of the
/// same file skips parsing. Returns NULL for data rlottie can't render.
RLottieBridgeAnimation *_Nullable rlottie_bridge_create(
    const char *_Nonnull json,
    size_t length,
    const char *_Nullable cacheKey
);

void rlottie_bridge_destroy(RLottieBridgeAnimation *_Nullable animation);

/// At least 1.
int32_t rlottie_bridge_frame_count(const RLottieBridgeAnimation *_Nonnull animation);

/// Frames per second, at least 1.
double rlottie_bridge_frame_rate(const RLottieBridgeAnimation *_Nonnull animation);

/// The animation's own size in points, at least 1 by 1.
void rlottie_bridge_size(const RLottieBridgeAnimation *_Nonnull animation, size_t *_Nonnull width, size_t *_Nonnull height);

/// Renders `frame` into `buffer` as premultiplied ARGB32 in native byte order, which is BGRA in memory on Apple
/// platforms (CGImage's byteOrder32Little with premultipliedFirst).
void rlottie_bridge_render(
    RLottieBridgeAnimation *_Nonnull animation,
    int32_t frame,
    uint32_t *_Nonnull buffer,
    size_t width,
    size_t height,
    size_t bytesPerRow
);

#ifdef __cplusplus
}
#endif

#endif
