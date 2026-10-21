import Foundation

/// How much the app may use of her location. "Restricted" counts as denied.
public enum LocationAccess: Hashable, Sendable {
    case notDetermined
    case allowed
    case denied
}

/// Her approximate location, only while the app is open (Phase 29).
///
/// Implementations ask for reduced accuracy, never full, and give back a `CoarseCoordinate`:
/// nothing finer ever leaves the implementation.
public protocol ApproximateLocationProvider: Sendable {
    func access() async -> LocationAccess
    /// Shows iOS's own prompt if she hasn't been asked yet. Returns where that left things.
    func requestAccess() async -> LocationAccess
    /// Where she is now, rounded. Throws `unavailable` when it can't be found or isn't allowed.
    func currentLocation() async throws(WeatherError) -> CoarseCoordinate
}

/// Finds a city by the name she types, so a city needs no location permission.
public protocol CityFinder: Sendable {
    /// A few matches, best first. An empty list means nothing matched; `unavailable` means the
    /// search couldn't run (offline).
    func cities(matching query: String) async throws(WeatherError) -> [WeatherPlace]
}

/// Where today's forecast comes from for a place: Apple WeatherKit, or a stand-in until the
/// WeatherKit capability is switched on.
public protocol WeatherForecastSource: Sendable {
    func forecast(at coordinate: CoarseCoordinate, now: Date) async throws(WeatherError) -> WeatherSnapshot
    /// The credit Apple requires wherever its weather shows. `nil` when the data isn't Apple's.
    func attribution() async -> WeatherCredit?
}

/// Apple Weather's required credit: its mark (light and dark versions) and the page with the
/// legal text for the data sources. Shown wherever forecast data shows.
public struct WeatherCredit: Hashable, Sendable {
    public var serviceName: String
    public var markLightURL: URL?
    public var markDarkURL: URL?
    public var legalURL: URL

    /// Apple's published page, used when the service can't be asked for the current one.
    public static let legalFallbackURL: URL =
        URL(string: "https://weatherkit.apple.com/legal-attribution.html") ?? URL(filePath: "/")

    public init(
        serviceName: String = "Apple Weather", markLightURL: URL? = nil, markDarkURL: URL? = nil,
        legalURL: URL = WeatherCredit.legalFallbackURL
    ) {
        self.serviceName = serviceName
        self.markLightURL = markLightURL
        self.markDarkURL = markDarkURL
        self.legalURL = legalURL
    }
}

/// No location: previews and tests that don't touch it. It behaves like a denied permission.
public struct UnavailableLocationProvider: ApproximateLocationProvider {
    public init() {}
    public func access() async -> LocationAccess { .denied }
    public func requestAccess() async -> LocationAccess { .denied }
    public func currentLocation() async throws(WeatherError) -> CoarseCoordinate { throw .unavailable }
}

/// No city search: finds nothing and says the search isn't available.
public struct UnavailableCityFinder: CityFinder {
    public init() {}
    public func cities(matching query: String) async throws(WeatherError) -> [WeatherPlace] { throw .unavailable }
}
