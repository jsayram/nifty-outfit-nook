import Foundation
import Models
import Synchronization

// Stand-ins for the parts of the weather chain that need Apple's services (Phase 29), so every
// state can be shown and tested on a simulator: the forecast, her location with each permission
// answer, and a short list of cities to search. Debug builds and tests only.

/// A forecast source that answers with a `WeatherProvider`'s weather, whatever the place. The
/// weather state a sample closet forces (`-fixtures demo:weather=snow`) is what shows, so the
/// whole chain, from her city to Home's window, can be tried without the WeatherKit capability.
public final class FixtureForecastSource: WeatherForecastSource {
    private let stand: any WeatherProvider
    private let credit: WeatherCredit?
    private let calls = Mutex<[CoarseCoordinate]>([])

    public init(standingIn provider: any WeatherProvider, credit: WeatherCredit? = WeatherCredit()) {
        stand = provider
        self.credit = credit
    }

    /// The places the source was asked about, in order.
    public var requested: [CoarseCoordinate] { calls.withLock { $0 } }

    public func forecast(at coordinate: CoarseCoordinate, now: Date) async throws(WeatherError) -> WeatherSnapshot {
        calls.withLock { $0.append(coordinate) }
        var snapshot = try await stand.currentWeather()
        // The real forecast has today's range and chance of rain; give the stand-in's the same.
        snapshot.lowCelsius = snapshot.lowCelsius ?? snapshot.temperatureCelsius - 5
        snapshot.highCelsius = snapshot.highCelsius ?? snapshot.temperatureCelsius + 3
        snapshot.precipitationChance =
            snapshot.precipitationChance
            ?? [WeatherCondition.rain: 0.7, .snow: 0.6, .cloudy: 0.2, .sun: 0][snapshot.condition]
        return snapshot
    }

    public func attribution() async -> WeatherCredit? { credit }
}

/// A location provider that answers as a scripted permission would.
public final class FixtureLocationProvider: ApproximateLocationProvider {
    private struct State {
        var access: LocationAccess
        var location: CoarseCoordinate?
    }

    private let state: Mutex<State>
    /// What she answers when asked: allow, or don't allow.
    private let grantsWhenAsked: Bool

    public init(access: LocationAccess, location: CoarseCoordinate? = nil, grantsWhenAsked: Bool = true) {
        state = Mutex(State(access: access, location: location))
        self.grantsWhenAsked = grantsWhenAsked
    }

    public func access() async -> LocationAccess { state.withLock { $0.access } }

    public func requestAccess() async -> LocationAccess {
        state.withLock {
            if $0.access == .notDetermined { $0.access = grantsWhenAsked ? .allowed : .denied }
            return $0.access
        }
    }

    public func currentLocation() async throws(WeatherError) -> CoarseCoordinate {
        let found = state.withLock { $0.access == .allowed ? $0.location : nil }
        guard let found else { throw .unavailable }
        return found
    }

    /// Changes the permission, as turning it off in Settings would.
    public func setAccess(_ access: LocationAccess) { state.withLock { $0.access = access } }
}

/// A city search over a short fixed list.
public struct FixtureCityFinder: CityFinder {
    public let isOffline: Bool

    public init(isOffline: Bool = false) { self.isOffline = isOffline }

    public static let known: [WeatherPlace] = [
        ("Seattle, WA", 47.61, -122.33), ("Portland, OR", 45.52, -122.68), ("Chicago, IL", 41.88, -87.63),
        ("Boston, MA", 42.36, -71.06), ("Austin, TX", 30.27, -97.74), ("Denver, CO", 39.74, -104.99),
        ("Phoenix, AZ", 33.45, -112.07), ("Miami, FL", 25.76, -80.19),
    ].compactMap { name, lat, lon in
        CoarseCoordinate(latitude: lat, longitude: lon).flatMap { WeatherPlace(name: name, coordinate: $0) }
    }

    public func cities(matching query: String) async throws(WeatherError) -> [WeatherPlace] {
        if isOffline { throw .unavailable }
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wanted.count >= 2 else { return [] }
        return Self.known.filter { $0.name.localizedCaseInsensitiveContains(wanted) }
    }
}
