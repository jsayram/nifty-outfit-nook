import Models

/// What the `-tour` debug launch flag asks of the tours (Phase 16a). Release builds always use
/// `standard`: the parser is compiled only in Debug, and `scripts/check-release.sh` checks the
/// flag isn't in a Release binary.
///
/// - `-tour home` starts Home's tour when Home first shows, whatever is recorded. Any tour's ID
///   works the same way (`-tour closet`, `-tour yourLooks`; see `TourID.all`).
/// - `-tour reset` forgets every tour seen and turns tips back on, before anything starts. In
///   Stage A progress is in memory, so a launch is already fresh; from Phase 21a it's on disk.
/// - `-tour off` turns "Show tips on new screens" off, so no tour starts by itself. The UI tests
///   use it, except the ones about tours.
///
/// Values can be combined with commas: `-tour reset,home`.
public struct TourLaunchOptions: Hashable, Sendable {
    public var startsTours: Set<TourID>
    public var resetsProgress: Bool
    public var turnsTipsOff: Bool

    public init(startsTours: Set<TourID> = [], resetsProgress: Bool = false, turnsTipsOff: Bool = false) {
        self.startsTours = startsTours
        self.resetsProgress = resetsProgress
        self.turnsTipsOff = turnsTipsOff
    }

    /// No flag: tours behave as they do for Lily.
    public static let standard = TourLaunchOptions()
}

#if DEBUG
    extension TourLaunchOptions {
        /// The launch argument.
        public static let launchArgument = "-tour"

        /// Reads `-tour <value>[,<value>]`. Unknown values are ignored; a missing flag is
        /// `standard`.
        public init(launchArguments: [String]) {
            self.init()
            guard let flag = launchArguments.firstIndex(of: Self.launchArgument),
                launchArguments.indices.contains(flag + 1)
            else { return }
            for value in launchArguments[flag + 1].split(separator: ",").map(String.init) {
                switch value {
                case "reset": resetsProgress = true
                case "off": turnsTipsOff = true
                default:
                    // Any tour's ID starts that tour once its screen shows (Phase 16b).
                    if let tour = TourID.all.first(where: { $0.rawValue == value }) {
                        startsTours.insert(tour)
                    }
                }
            }
        }
    }
#endif
