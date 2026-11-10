import Foundation
import Models

/// Her appearance choice (N3), kept on the iPhone in a `UserDefaults` suite only this app can
/// read. It holds one word: system, light or dark. Delete my data removes it, so the app follows
/// the iPhone again.
public final class DefaultsAppearanceStore: AppearanceStore, @unchecked Sendable {
    public static let suiteName = "com.jsayram.niftyoutfitnook.appearance"
    static let key = "appearance.choice"

    // UserDefaults is thread-safe, which is why this class can be shared.
    private let defaults: UserDefaults

    public init(suiteName: String = DefaultsAppearanceStore.suiteName) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Anything missing or unreadable follows the iPhone.
    public func current() -> AppearanceChoice {
        defaults.string(forKey: Self.key).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }

    public func save(_ choice: AppearanceChoice) {
        if choice == .system {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(choice.rawValue, forKey: Self.key)
        }
    }

    public func eraseAll() async throws(StoreError) {
        defaults.removeObject(forKey: Self.key)
    }
}
