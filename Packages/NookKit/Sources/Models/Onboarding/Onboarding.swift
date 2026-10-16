import Foundation

// First run (Phase 17, PRD §7 Onboarding row, §5.1 "First launch", FR-73 for the hand-off to
// Home's tour).
//
// What's kept about onboarding is app state, not her data: whether she has finished it and which
// starting closet she picked. No name, no fit, nothing she typed. `closet/DATA_MAP.md` puts these
// flags in the lowest tier, so Stage A keeps them across launches in the app's own
// `UserDefaults` suite (`Services/AppState`). Her answers (the name on the sign, her usual fit)
// go to the profile store like any other profile change, which in Stage A is in memory.

/// The closet the app starts with, chosen on the last onboarding step. Stage A has no real
/// storage, so a test build either shows the sample closet or starts empty.
public enum StartingCloset: String, CaseIterable, Codable, Hashable, Sendable {
    /// The demo closet: example pieces, looks, suitcases and pictures, so Style Me works at once.
    case sample
    /// Nothing yet. What she adds lasts until the app closes, in Stage A.
    case empty
}

/// What's kept about onboarding across launches.
public struct OnboardingState: Hashable, Codable, Sendable {
    /// She reached Home through onboarding (or "I already use Nifty Outfit Nook").
    public var isCompleted: Bool
    /// The closet she started with. `nil` until she finishes.
    public var startingCloset: StartingCloset?

    public init(isCompleted: Bool = false, startingCloset: StartingCloset? = nil) {
        self.isCompleted = isCompleted
        self.startingCloset = startingCloset
    }

    /// A fresh install, and the state after Delete my data.
    public static let fresh = OnboardingState()
}

/// What she chose on the way through onboarding. The name and the fit are her data and go to the
/// profile; only `startingCloset` is kept as app state.
public struct OnboardingAnswers: Hashable, Sendable {
    /// The name on her sign, already checked with `NameRules.signName`. Empty means the sign
    /// says Hello (RD-03.2).
    public var signName: String
    /// How she likes clothes to sit, or `nil` when she skipped it.
    public var usualFit: Comfort?
    public var startingCloset: StartingCloset

    public init(signName: String = "", usualFit: Comfort? = nil, startingCloset: StartingCloset = .sample) {
        self.signName = signName
        self.usualFit = usualFit
        self.startingCloset = startingCloset
    }

    /// "I already use Nifty Outfit Nook": straight to Home with the sample closet, nothing asked.
    public static let alreadyUsing = OnboardingAnswers()

    /// Writes the answers into a profile. A skipped fit leaves the profile's own.
    public func apply(to profile: inout Profile) {
        profile.signName = signName
        if let usualFit {
            profile.usualFit = usualFit
        }
    }
}

/// Where the onboarding state is kept. Features read and write it only through this protocol.
/// Delete my data erases it with the profile, so the app opens on onboarding again.
public protocol OnboardingStateStore: ErasableStore {
    func state() async throws(StoreError) -> OnboardingState
    /// Onboarding is done, starting from `closet`.
    func complete(startingCloset closet: StartingCloset) async throws(StoreError)
}
