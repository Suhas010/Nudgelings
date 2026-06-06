// swift-tools-version: 6.0
import Foundation
import PackageDescription

// DRIP_CORE_ONLY=1 builds just the logic + tests (handy while the app layer is mid-change).
let coreOnly = ProcessInfo.processInfo.environment["DRIP_CORE_ONLY"] != nil

let app: [Target] = coreOnly ? [] : [
    .executableTarget(
        name: "Drip",
        dependencies: ["DripCore"],
        // AppKit/SwiftUI glue; strict Swift 6 concurrency adds noise without catching real bugs here.
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]

let package = Package(
    name: "Drip",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DripCore"),
        .testTarget(name: "DripCoreTests", dependencies: ["DripCore"]),
    ] + app
)
