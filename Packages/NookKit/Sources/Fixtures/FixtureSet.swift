/// The sample data set the app runs on during Stage A.
///
/// UI tests choose one with a launch argument, for example `-fixtures empty`. A behaviour can
/// follow after a colon, for example `-fixtures demo:offline` (see `FixtureBehavior`).
public enum FixtureSet: String, CaseIterable, Sendable {
    /// The demo closet: 21 garments, a few looks, six suitcases and a profile named Lily.
    case demo
    /// A fresh install: no garments, looks or suitcases, and default preferences.
    case empty
    /// A generated closet with more than 2,000 garments, many looks and suitcases.
    case large

    /// The launch argument that names a fixture set.
    public static let launchArgument = "-fixtures"

    /// Reads `-fixtures <name>[:<behavior>]` from the launch arguments.
    ///
    /// A missing flag, a missing value or an unknown name all give `.demo`.
    public init(launchArguments: [String]) {
        self = FixtureConfiguration(launchArguments: launchArguments).set
    }
}

/// How the fixture services behave, for loading, error and offline states.
public enum FixtureBehavior: String, CaseIterable, Sendable {
    /// Everything answers at once and works.
    case normal
    /// Every call waits: stores about half a second, weather a second, the stylist a few seconds.
    case slow
    /// No connection: the stylist throws `offline` and the weather can't be read. Local stores work.
    case offline
    /// The stylist runs but doesn't finish (`StylistError.notCompleted`).
    case stylistFails = "stylist-fails"
    /// The stylist returns two versions instead of three.
    case stylistPartial = "stylist-partial"
    /// Every store call fails with `StoreError.unavailable`, for error states.
    case storesFail = "stores-fail"
}

/// A fixture set plus a behaviour, as read from `-fixtures <set>[:<behavior>]`.
public struct FixtureConfiguration: Hashable, Sendable {
    public var set: FixtureSet
    public var behavior: FixtureBehavior

    public init(set: FixtureSet = .demo, behavior: FixtureBehavior = .normal) {
        self.set = set
        self.behavior = behavior
    }

    /// Unknown or missing parts fall back to `demo` and `normal`.
    public init(launchArguments: [String]) {
        guard
            let flagIndex = launchArguments.firstIndex(of: FixtureSet.launchArgument),
            launchArguments.indices.contains(flagIndex + 1)
        else {
            self.init()
            return
        }
        let parts = launchArguments[flagIndex + 1].split(separator: ":", maxSplits: 1).map(String.init)
        self.init(
            set: parts.first.flatMap(FixtureSet.init(rawValue:)) ?? .demo,
            behavior: parts.dropFirst().first.flatMap(FixtureBehavior.init(rawValue:)) ?? .normal
        )
    }
}
