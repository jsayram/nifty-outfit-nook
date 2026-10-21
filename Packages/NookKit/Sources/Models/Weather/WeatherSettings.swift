import Foundation
import Synchronization

/// A place she chose by name, with its rounded coordinates. Never her exact position.
public struct WeatherPlace: Hashable, Sendable, Codable {
    /// The longest name kept.
    public static let nameLimit = 80

    public let name: String
    public let coordinate: CoarseCoordinate

    /// `nil` when the name is empty after trimming.
    public init?(name: String, coordinate: CoarseCoordinate) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.name = String(trimmed.prefix(Self.nameLimit))
        self.coordinate = coordinate
    }

    private enum CodingKeys: String, CodingKey {
        case name, coordinate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let coordinate = try container.decode(CoarseCoordinate.self, forKey: .coordinate)
        guard let place = WeatherPlace(name: name, coordinate: coordinate) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No name."))
        }
        self = place
    }
}

/// What she chose for live weather (Phase 29, "Live weather" in Privacy and terms).
///
/// Off until she turns it on. A city she picks needs no permission at all. "Use my location" is
/// optional: approximate, only while the app is open, and it falls back to the city whenever it
/// can't be used. Her location itself is never kept here, only the city she picked.
public struct WeatherSettings: Hashable, Sendable, Codable {
    public var isOn: Bool
    public var usesMyLocation: Bool
    public var city: WeatherPlace?

    public init(isOn: Bool = false, usesMyLocation: Bool = false, city: WeatherPlace? = nil) {
        self.isOn = isOn
        self.usesMyLocation = usesMyLocation
        self.city = city
    }

    public static let off = WeatherSettings()
}

/// Where her weather choices are kept. They're Personal (a city is a place she cares about) and
/// stay on the iPhone. Delete my data empties them.
public protocol WeatherSettingsStore: ErasableStore {
    func current() -> WeatherSettings
    func save(_ settings: WeatherSettings)
}

/// Weather choices in memory: previews, tests and the debug sample closet.
public final class InMemoryWeatherSettingsStore: WeatherSettingsStore {
    private let state: Mutex<WeatherSettings>

    public init(_ settings: WeatherSettings = .off) {
        state = Mutex(settings)
    }

    public func current() -> WeatherSettings { state.withLock { $0 } }

    public func save(_ settings: WeatherSettings) { state.withLock { $0 = settings } }

    public func eraseAll() async throws(StoreError) { state.withLock { $0 = .off } }
}
