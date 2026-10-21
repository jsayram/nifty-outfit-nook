import Foundation
import Models

/// Her yes to the cloud stylist's provider (Phase 27a), kept on the iPhone in a `UserDefaults`
/// suite only this app can read: the consent text's version and when she agreed. Delete my data
/// removes it, and so does turning the switch off in Privacy and terms.
public final class DefaultsStylistConsentStore: StylistConsentStore, @unchecked Sendable {
    public static let suiteName = "com.jsayram.niftyoutfitnook.consent"
    static let key = "stylist.consent"

    // UserDefaults is thread-safe, which is why this class can be shared.
    private let defaults: UserDefaults

    public init(suiteName: String = DefaultsStylistConsentStore.suiteName) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Anything unreadable reads as no consent, so a damaged value can't send anything.
    public func current() -> StylistConsent? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(StylistConsent.self, from: data)
    }

    public func save(_ consent: StylistConsent?) {
        guard let consent, let data = try? JSONEncoder().encode(consent) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    public func eraseAll() async throws(StoreError) {
        defaults.removeObject(forKey: Self.key)
    }
}
