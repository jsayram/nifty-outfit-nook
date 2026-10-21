import Foundation
import Models

/// Her weather choices, kept on the iPhone in a `UserDefaults` suite only this app can read
/// (Phase 29). It holds on or off, "Use my location" on or off, and the city she picked with its
/// rounded coordinates. Never her position. Delete my data removes it.
public final class DefaultsWeatherSettingsStore: WeatherSettingsStore, @unchecked Sendable {
    public static let suiteName = "com.jsayram.niftyoutfitnook.weather"
    static let key = "weather.settings"

    // UserDefaults is thread-safe, which is why this class can be shared.
    private let defaults: UserDefaults

    public init(suiteName: String = DefaultsWeatherSettingsStore.suiteName) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Anything unreadable reads as off, so a damaged value can't switch weather on.
    public func current() -> WeatherSettings {
        guard let data = defaults.data(forKey: Self.key),
            let settings = try? JSONDecoder().decode(WeatherSettings.self, from: data)
        else { return .off }
        return settings
    }

    public func save(_ settings: WeatherSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func eraseAll() async throws(StoreError) {
        defaults.removeObject(forKey: Self.key)
    }
}
