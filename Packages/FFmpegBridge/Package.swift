// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FFmpegBridge",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "FFmpegBridge", targets: ["FFmpegBridge"]),
    ],
    targets: [
        .binaryTarget(
            name: "FFmpegBinary",
            url: "https://github.com/flocked/ffmpeg-apple-xcframeworks/releases/download/FFmpeg-9.0/FFmpeg-iOS.xcframework.zip",
            checksum: "caec32e296e2398a586576e4100b58c5560c34272f760dbad262b704f8a539af",
        ),
        .target(
            name: "FFmpegBridge",
            dependencies: ["FFmpegBinary"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("z"),
            ],
        ),
    ],
)
