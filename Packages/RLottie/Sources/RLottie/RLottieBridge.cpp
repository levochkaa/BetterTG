// RLottieBridge.cpp

#include "RLottieBridge.h"

#include "rlottie.h"

#include <algorithm>
#include <memory>
#include <string>

struct RLottieBridgeAnimation {
    std::unique_ptr<rlottie::Animation> animation;
};

RLottieBridgeAnimation *rlottie_bridge_create(const char *json, size_t length, const char *cacheKey) {
    std::string key = cacheKey != nullptr ? cacheKey : "";
    auto animation = rlottie::Animation::loadFromData(std::string(json, length), key, "", !key.empty());
    if (animation == nullptr) {
        return nullptr;
    }
    return new RLottieBridgeAnimation{std::move(animation)};
}

void rlottie_bridge_destroy(RLottieBridgeAnimation *animation) {
    delete animation;
}

int32_t rlottie_bridge_frame_count(const RLottieBridgeAnimation *animation) {
    return std::max<int32_t>(1, static_cast<int32_t>(animation->animation->totalFrame()));
}

double rlottie_bridge_frame_rate(const RLottieBridgeAnimation *animation) {
    return std::max(1.0, animation->animation->frameRate());
}

void rlottie_bridge_size(const RLottieBridgeAnimation *animation, size_t *width, size_t *height) {
    size_t w = 0;
    size_t h = 0;
    animation->animation->size(w, h);
    *width = std::max<size_t>(1, w);
    *height = std::max<size_t>(1, h);
}

void rlottie_bridge_render(
    RLottieBridgeAnimation *animation,
    int32_t frame,
    uint32_t *buffer,
    size_t width,
    size_t height,
    size_t bytesPerRow
) {
    rlottie::Surface surface(buffer, width, height, bytesPerRow);
    animation->animation->renderSync(static_cast<size_t>(std::max(0, frame)), surface);
}
