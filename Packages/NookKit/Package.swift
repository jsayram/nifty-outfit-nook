// swift-tools-version: 6.2

import PackageDescription

// NookKit holds almost all of the app's code. The app target only wires it together.
// See docs/decisions/0001-technical-decisions.md for the module layout.

/// Every target treats warnings as errors (decision 0001, item 5).
let strictSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error)
]

/// UI modules also default to main-actor isolation, like the app target. Background work is explicit.
let uiSettings: [SwiftSetting] =
    strictSettings + [
        .defaultIsolation(MainActor.self)
    ]

let package = Package(
    name: "NookKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Fixtures", targets: ["Fixtures"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            exclude: ["README.md"],
            resources: [.process("Resources")],
            swiftSettings: uiSettings
        ),
        .target(name: "Models", swiftSettings: strictSettings),
        .target(name: "Fixtures", dependencies: ["Models"], swiftSettings: strictSettings),
        .target(
            name: "Features",
            dependencies: ["DesignSystem", "Models"],
            resources: [.process("Resources")],
            swiftSettings: uiSettings
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"], swiftSettings: strictSettings),
        .testTarget(name: "ModelsTests", dependencies: ["Models"], swiftSettings: strictSettings),
        .testTarget(name: "FixturesTests", dependencies: ["Fixtures"], swiftSettings: strictSettings),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"], swiftSettings: strictSettings),
    ],
    swiftLanguageModes: [.v6]
)
