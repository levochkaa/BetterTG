# RLottie

Telegram-iOS's rlottie fork (`submodules/rlottie/rlottie` at `67f103bc8b625f2a4a9e94f1d8c7bd84c5a08d1d`), vendored
for rendering TGS stickers and emoji off the main thread, plus `RLottieBridge`, a small C interface in the shape of
Telegram-iOS's `RLottieInstance`.

Only the library's sources are copied: the bindings, the stb image loader, the NEON drawing helper and rapidjson's
`msinttypes` are left out, as Telegram-iOS's build leaves them out. `config.h` is Telegram-iOS's.

rlottie is LGPL-2.1-or-later, with FreeType, pixman, stb and rapidjson parts under their own licenses; see
`LICENSES/`.
