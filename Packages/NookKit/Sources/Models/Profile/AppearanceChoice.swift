import Synchronization

/// Light or dark for the whole app (N3, decided 6 November 2026). The app follows the iPhone
/// until she first chooses, with the lamp in her room or the Dark mode switch in Profile. After
/// that her choice wins, across launches.
///
/// Data tier: **Device** (a display preference; nothing personal).
public enum AppearanceChoice: String, CaseIterable, Hashable, Sendable, Codable {
    /// Follow the iPhone's appearance. The default, until she chooses.
    case system
    case light
    case dark
}

/// Where her appearance choice lives. Reading and writing are quick and local, so the choice
/// is read once at launch, before the first screen draws.
public protocol AppearanceStore: ErasableStore {
    func current() -> AppearanceChoice
    func save(_ choice: AppearanceChoice)
}

/// The appearance choice in memory: previews, tests and the debug `-onboarding skip` launches,
/// so each UI test starts from the iPhone's appearance.
public final class InMemoryAppearanceStore: AppearanceStore {
    private let state: Mutex<AppearanceChoice>

    public init(_ choice: AppearanceChoice = .system) {
        state = Mutex(choice)
    }

    public func current() -> AppearanceChoice { state.withLock { $0 } }

    public func save(_ choice: AppearanceChoice) { state.withLock { $0 = choice } }

    public func eraseAll() async throws(StoreError) { state.withLock { $0 = .system } }
}
