/// What the `-onboarding` debug launch flag asks for (Phase 17). Release builds always use
/// `standard`: the parser is compiled only in Debug, and `scripts/check-release.sh` checks the
/// flag isn't in a Release binary.
///
/// - `-onboarding reset` forgets that onboarding was finished, before anything reads it, so the
///   app opens on the welcome as on a fresh install. With `-tour reset` it's a fresh install for
///   the tours too.
/// - `-onboarding skip` opens Home straight away for this launch, on the `-fixtures` set as it
///   is, and writes nothing. Every UI test passes it, except the onboarding tests. Delete my
///   data still opens onboarding.
nonisolated public enum OnboardingLaunchOptions: Hashable, Sendable {
    /// No flag: onboarding shows until she finishes it, as for Lily.
    case standard
    case reset
    case skip
}

#if DEBUG
    extension OnboardingLaunchOptions {
        /// The launch argument.
        public static let launchArgument = "-onboarding"

        /// Reads `-onboarding reset` or `-onboarding skip`. Anything else is `standard`.
        public init(launchArguments: [String]) {
            guard let flag = launchArguments.firstIndex(of: Self.launchArgument),
                launchArguments.indices.contains(flag + 1)
            else {
                self = .standard
                return
            }
            switch launchArguments[flag + 1] {
            case "reset": self = .reset
            case "skip": self = .skip
            default: self = .standard
            }
        }
    }
#endif
