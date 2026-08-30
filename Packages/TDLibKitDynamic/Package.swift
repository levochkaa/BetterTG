// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TDLibKitDynamic",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "TDLibKitDynamic",
            type: .dynamic,
            targets: ["TDLibKitDynamic"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Swiftgram/TDLibKit",
            exact: "1.5.2-tdlib-1.8.66-022d6020"
        ),
    ],
    targets: [
        .target(
            name: "TDLibKitDynamic",
            dependencies: [
                .product(name: "TDLibKit", package: "TDLibKit"),
            ]
        ),
    ]
)
