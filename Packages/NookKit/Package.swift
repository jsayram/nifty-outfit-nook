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
        .library(name: "Services", targets: ["Services"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "BetterAuth", targets: ["BetterAuth"]),
    ],
    // swift-snapshot-testing is test-only (decision 0001, items 8 and 10; vetting in
    // docs/decisions/0002-snapshot-testing.md). Nothing third-party ships in the app: sign-in is
    // our own client for Better Auth (BA4), which replaced clerk-ios. Never add a dependency
    // without Jose's written approval.
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            exclude: ["README.md"],
            resources: [.process("Resources")],
            swiftSettings: uiSettings
        ),
        .target(name: "Models", swiftSettings: strictSettings),
        // The sample wardrobe's code. Its photos are not a resource of this target, because SwiftPM
        // copies a package's resources into every configuration, Release included. They live once in
        // Tests/NookTestSupport/SampleWardrobe: the package tests get them from that target, and the
        // app copies the same folder into Debug builds only (Configs/Release.xcconfig excludes it).
        .target(name: "Fixtures", dependencies: ["Models"], swiftSettings: strictSettings),
        // Real services built on Apple frameworks only (decision 0001, item 4). Phase 8a adds
        // on-device subject lifting with Vision.
        .target(name: "Services", dependencies: ["Models"], swiftSettings: strictSettings),
        // The backend gateway (Phase 24a): the v1 contract types, the URLSession client, the
        // account service, and the in-process fake backend the app runs on until the backend
        // address is configured. Apple frameworks only.
        .target(name: "Networking", dependencies: ["Models"], swiftSettings: strictSettings),
        // Sign in with Apple through Better Auth in our Convex deployment (BA4): the client for the
        // contract's signIn routes, the session in the Keychain, and the real gateway. Apple
        // frameworks only.
        .target(name: "BetterAuth", dependencies: ["Models", "Networking"], swiftSettings: strictSettings),
        .target(
            name: "Features",
            dependencies: ["DesignSystem", "Models"],
            resources: [.process("Resources")],
            swiftSettings: uiSettings
        ),
        // Test-only helpers every test target shares: the fixed test time, the speed checks and the
        // store contracts that every store, in-memory or real, has to pass, and the sample
        // wardrobe's photos (the single copy in the repo). Only test targets depend on it, so none
        // of it reaches the app.
        .target(
            name: "NookTestSupport", dependencies: ["Models"], path: "Tests/NookTestSupport",
            resources: [.copy("SampleWardrobe")],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: [
                "DesignSystem",
                "NookTestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: strictSettings
        ),
        .testTarget(name: "ModelsTests", dependencies: ["Models", "NookTestSupport"], swiftSettings: strictSettings),
        .testTarget(
            name: "FixturesTests", dependencies: ["Fixtures", "Models", "NookTestSupport"],
            swiftSettings: strictSettings
        ),
        // Backup/Fixtures holds an export from every shipped backup format version (Phase 21b).
        .testTarget(
            name: "ServicesTests", dependencies: ["Services", "Models", "Fixtures", "NookTestSupport"],
            resources: [.copy("Backup/Fixtures")], swiftSettings: strictSettings),
        // Phase 20a persistence spike: SwiftData, migrations, recovery and sync, tested here and
        // never shipped (docs/decisions/0003-persistence-spike.md). KillHarness builds the files
        // in Spike/ as a macOS tool that kills itself mid-migration.
        // Contract/ is a byte-identical copy of the backend repo's contract (its golden examples);
        // the tests check the Swift types and the fake backend against it.
        .testTarget(
            name: "NetworkingTests", dependencies: ["Networking", "Models", "NookTestSupport"],
            resources: [.copy("Contract")], swiftSettings: strictSettings),
        .testTarget(
            name: "BetterAuthTests", dependencies: ["BetterAuth", "Networking", "Models", "NookTestSupport"],
            swiftSettings: strictSettings),
        .testTarget(
            name: "PersistenceSpikeTests", dependencies: ["Models", "Fixtures", "NookTestSupport"],
            exclude: ["KillHarness"], swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: [
                "Features",
                "Models",
                "Fixtures",
                "DesignSystem",
                "NookTestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: [
                "Home/__Snapshots__", "Closet/__Snapshots__", "Garment/__Snapshots__", "AddPiece/__Snapshots__",
                "Looks/__Snapshots__", "StyleMe/__Snapshots__", "Swap/__Snapshots__", "LookBuilder/__Snapshots__",
                "SavedLooks/__Snapshots__", "Suitcases/__Snapshots__", "Profile/__Snapshots__",
                "Settings/__Snapshots__", "Tours/__Snapshots__", "Onboarding/__Snapshots__", "TryOn/__Snapshots__",
            ],
            swiftSettings: strictSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
