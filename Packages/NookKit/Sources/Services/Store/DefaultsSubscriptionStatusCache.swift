import Foundation
import Models

/// The last subscription status, in `UserDefaults`, so the app can show it before StoreKit
/// answers at launch. It holds only the state, product ID and dates: no transaction IDs, nothing
/// that identifies her. It isn't proof of anything: `hasStylingAccess(at:)` never grants past its
/// dates, StoreKit replaces it on every read, and the server never sees it except as a hint.
public final class DefaultsSubscriptionStatusCache: SubscriptionStatusCache, @unchecked Sendable {
    // `UserDefaults` is thread-safe; it isn't marked Sendable.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "nook.subscription.status") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> SubscriptionStatus? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SubscriptionStatus.self, from: data)
    }

    public func save(_ status: SubscriptionStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: key)
    }
}
