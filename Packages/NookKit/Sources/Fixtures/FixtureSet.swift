/// The sample data set the app runs on during Stage A.
///
/// UI tests choose one with a launch argument, for example `-fixtures empty`.
/// The sets themselves arrive in Phase 3; for now the choice is parsed and nothing else happens.
public enum FixtureSet: String, CaseIterable, Sendable {
    /// The demo closet.
    case demo
    /// No garments, looks or suitcases.
    case empty
    /// A generated closet with more than 2,000 garments.
    case large

    /// The launch argument that names a fixture set.
    public static let launchArgument = "-fixtures"

    /// Reads `-fixtures <name>` from the launch arguments.
    ///
    /// A missing flag, a missing value or an unknown name all give `.demo`.
    public init(launchArguments: [String]) {
        guard
            let flagIndex = launchArguments.firstIndex(of: Self.launchArgument),
            launchArguments.indices.contains(flagIndex + 1),
            let set = FixtureSet(rawValue: launchArguments[flagIndex + 1])
        else {
            self = .demo
            return
        }
        self = set
    }
}
