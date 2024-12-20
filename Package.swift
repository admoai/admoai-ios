// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AdMoai",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "AdMoai",
            targets: ["AdMoai"])
    ],
    targets: [
        .target(
            name: "AdMoai"),
        .testTarget(
            name: "AdMoaiTests",
            dependencies: ["AdMoai"]
        ),
    ]
)
