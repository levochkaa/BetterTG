// swift-tools-version: 5.9

import PackageDescription

// Telegram's rlottie fork (telegramdesktop/rlottie as Telegram-iOS pins it), built as Telegram-iOS's RLottieBinding
// is: NEON and the image loader off, the model cache thread-safe. `-w` keeps the vendored library's own warnings out
// of the app's build, as Xcode does for remote packages.
let package = Package(
    name: "RLottie",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "RLottie", targets: ["RLottie"]),
    ],
    targets: [
        .target(
            name: "RLottie",
            path: "Sources/RLottie",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("rlottie/inc"),
                .headerSearchPath("rlottie/src/vector"),
                .headerSearchPath("rlottie/src/vector/pixman"),
                .headerSearchPath("rlottie/src/vector/freetype"),
                .define("LOTTIE_DISABLE_ARM_NEON", to: "1"),
                .define("LOTTIE_THREAD_SAFE", to: "1"),
                .define("LOTTIE_IMAGE_MODULE_DISABLED", to: "1"),
                .define("pixman_region_selfcheck(x)", to: "1"),
                .unsafeFlags(["-w"]),
            ],
        ),
    ],
    cxxLanguageStandard: .cxx14,
)
