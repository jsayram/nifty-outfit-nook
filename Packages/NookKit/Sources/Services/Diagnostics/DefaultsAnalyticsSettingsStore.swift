import Foundation
import Models

/// "Help improve the app" (F1, D24), kept on the iPhone in the consent `UserDefaults` suite only
/// this app can read: the consent text's version, when she agreed and the random analytics ID.
/// Delete my data removes it, and so does turning the switch off in Privacy and terms (F1c: which
/// keeps the old ID here only until the server has deleted its events).
public final class DefaultsAnalyticsSettingsStore: AnalyticsSettingsStore, @unchecked Sendable {
    static let key = "analytics.settings"
    static let pendingKey = "analytics.pendingDeletions"

    // UserDefaults is thread-safe, which is why this class can be shared.
    private let defaults: UserDefaults

    public init(suiteName: String = DefaultsStylistConsentStore.suiteName) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Anything unreadable reads as off, so a damaged value can't send anything.
    public func current() -> AnalyticsSettings? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(AnalyticsSettings.self, from: data)
    }

    public func save(_ settings: AnalyticsSettings?) {
        guard let settings, let data = try? JSONEncoder().encode(settings) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    public func pendingDeletions() -> [String] {
        defaults.stringArray(forKey: Self.pendingKey) ?? []
    }

    public func savePendingDeletions(_ ids: [String]) {
        if ids.isEmpty {
            defaults.removeObject(forKey: Self.pendingKey)
        } else {
            defaults.set(ids, forKey: Self.pendingKey)
        }
    }

    public func eraseAll() async throws(StoreError) {
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.pendingKey)
    }
}
