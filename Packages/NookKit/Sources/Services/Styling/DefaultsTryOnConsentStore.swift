import Foundation
import Models

/// Her yes to the try-on image provider (Phase 33a, D1), kept on the iPhone in a `UserDefaults`
/// suite only this app can read: the consent text's version and when she agreed. Delete my data
/// removes it, and so does turning the switch off in Privacy and terms. It also keeps whether she
/// has seen the privacy walkthrough (33c), which turning the switch off leaves alone.
public final class DefaultsTryOnConsentStore: TryOnConsentStore, @unchecked Sendable {
    public static let suiteName = "com.jsayram.niftyoutfitnook.consent"
    static let key = "tryOn.consent"
    static let walkthroughKey = "tryOn.walkthroughSeen"

    // UserDefaults is thread-safe, which is why this class can be shared.
    private let defaults: UserDefaults

    public init(suiteName: String = DefaultsTryOnConsentStore.suiteName) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Anything unreadable reads as no consent, so a damaged value can't send anything.
    public func current() -> TryOnConsent? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(TryOnConsent.self, from: data)
    }

    public func save(_ consent: TryOnConsent?) {
        guard let consent, let data = try? JSONEncoder().encode(consent) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    public func hasSeenWalkthrough() -> Bool { defaults.bool(forKey: Self.walkthroughKey) }

    public func markWalkthroughSeen() { defaults.set(true, forKey: Self.walkthroughKey) }

    public func eraseAll() async throws(StoreError) {
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.walkthroughKey)
    }
}
