// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mely",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Mely", targets: ["MelyApp"]),
        .executable(name: "nc-hook", targets: ["NCHook"]),
        .executable(name: "mely-snapshots", targets: ["MelySnapshots"]),
    ],
    dependencies: [
        // In-app updates from the GitHub releases (appcast.xml + EdDSA-signed dmg).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Logic without UI: hooks, sessions, integrations, policies. Everything testable lives here.
        .target(name: "MelyCore"),
        // SwiftUI views shared by the app and the snapshot renderer.
        .target(name: "MelyUI", dependencies: ["MelyCore"]),
        .executableTarget(name: "MelyApp", dependencies: ["MelyCore", "MelyUI",
                                                        .product(name: "Sparkle", package: "Sparkle")]),
        // Hook relay called by Claude Code; must stay tiny and never block.
        .executableTarget(name: "NCHook", dependencies: ["MelyCore"]),
        // Renders UI states to PNG (stands in for SwiftUI Previews without Xcode).
        .executableTarget(name: "MelySnapshots", dependencies: ["MelyCore", "MelyUI"]),
        // Run with scripts/test.sh: it adds the Swift Testing paths the Command Line Tools need.
        .testTarget(name: "MelyCoreTests", dependencies: ["MelyCore"]),
    ]
)
