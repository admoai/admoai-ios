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
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "AdMoai"),
        .testTarget(
            name: "AdMoaiTests",
            dependencies: ["AdMoai"],
            // Documentation, the committed E2E report, and a read-only DB snapshot — not test
            // resources. The E2E runner lives in its own executable target and asserts against a
            // live engine; it never reads these. Excluded so SwiftPM does not treat them as
            // unhandled files.
            exclude: ["E2E"]
        ),
        // The Demo's pure ad-click logic, built here only so `swift test` can cover it.
        // Deliberately NOT a package product: consumers of the AdMoai library never build it.
        // The sources live inside the Demo app (Xcode 16 synchronized folder, so the app target
        // picks them up with no project edit); this target compiles the same files a second time.
        // Keep this directory free of UIKit/SwiftUI so it stays buildable on every platform.
        .target(
            name: "SampleSupport",
            dependencies: ["AdMoai"],
            path: "Examples/Demo/Demo/ClickHandling"
        ),
        .testTarget(
            name: "SampleSupportTests",
            dependencies: ["SampleSupport"]
        ),
        // Journey Ads live E2E runner. Deliberately an executable target and deliberately NOT
        // exposed as a package product: `swift test` therefore stays hermetic and offline by
        // construction (it cannot pick this up), while consumers depending on the AdMoai
        // library never build it. `swift build` does compile it, so the runner cannot rot
        // silently against SDK changes. See Tools/JourneyE2E/README.md.
        .executableTarget(
            name: "journey-e2e",
            dependencies: ["AdMoai"],
            path: "Tools/JourneyE2E",
            exclude: ["README.md"]
        ),
    ]
)
