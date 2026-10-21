import Foundation

/// The weather service the app uses (Phase 29): today's forecast for the place she chose, kept
/// per place and hour.
///
/// - Off, the settings pass the question to `whenOff` (the stand-in weather in a sample closet),
///   or say the weather isn't available.
/// - On with "Use my location", it asks `location` for a rounded position, and falls back to her
///   city when that isn't allowed or can't be found. Without a city either, nothing is shown.
/// - A forecast is fetched at most once per place and hour; between times it comes from memory,
///   and nothing polls. If a fetch fails (offline, or the service is over its limit), the last
///   forecast for that place is used for up to `staleLimit`, then the weather reads as
///   unavailable. Style Me still works without it (LR-04.3).
/// - Nothing about where she is is kept: the cache is in memory only and holds rounded
///   coordinates, and a forecast carries none.
public actor PlaceWeatherProvider: WeatherProvider {
    /// How long an old forecast stands in when a fresh one can't be fetched.
    public static let staleLimit: TimeInterval = 3 * 3600
    /// How long a rounded position found through "Use my location" is reused.
    public static let locationLifetime: TimeInterval = 3600

    private struct Key: Hashable {
        let coordinate: CoarseCoordinate
        let hour: Int
    }

    private let settings: any WeatherSettingsStore
    private let location: any ApproximateLocationProvider
    private let source: any WeatherForecastSource
    private let whenOff: (any WeatherProvider)?
    private let now: @Sendable () -> Date

    private var forecasts: [CoarseCoordinate: (snapshot: WeatherSnapshot, fetchedAt: Date, hour: Int)] = [:]
    private var inFlight: [Key: Task<Result<WeatherSnapshot, WeatherError>, Never>] = [:]
    private var lastLocation: (coordinate: CoarseCoordinate, at: Date)?
    /// How many times the source was asked, for tests.
    public private(set) var fetchCount = 0

    public init(
        settings: any WeatherSettingsStore, location: any ApproximateLocationProvider,
        source: any WeatherForecastSource, whenOff: (any WeatherProvider)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.location = location
        self.source = source
        self.whenOff = whenOff
        self.now = now
    }

    public func currentWeather() async throws(WeatherError) -> WeatherSnapshot {
        let choice = settings.current()
        guard choice.isOn else {
            guard let whenOff else { throw .unavailable }
            return try await whenOff.currentWeather()
        }
        guard let coordinate = await coordinate(for: choice) else { throw .unavailable }
        let time = now()
        let key = Key(coordinate: coordinate, hour: Self.hour(of: time))
        if let known = forecasts[coordinate], known.hour == key.hour { return known.snapshot }

        let task: Task<Result<WeatherSnapshot, WeatherError>, Never>
        if let running = inFlight[key] {
            task = running
        } else {
            fetchCount += 1
            let source = source
            task = Task {
                do throws(WeatherError) {
                    return .success(try await source.forecast(at: coordinate, now: time))
                } catch {
                    return .failure(error)
                }
            }
            inFlight[key] = task
        }
        let result = await task.value
        inFlight[key] = nil
        if Task.isCancelled { throw .cancelled }

        switch result {
        case .success(let snapshot):
            forecasts[coordinate] = (snapshot, time, key.hour)
            // Only the newest forecast per place is kept, and places she left don't pile up.
            forecasts = forecasts.filter { time.timeIntervalSince($0.value.fetchedAt) < Self.staleLimit }
            return snapshot
        case .failure(let error):
            if error != .cancelled, let old = forecasts[coordinate],
                time.timeIntervalSince(old.fetchedAt) < Self.staleLimit
            {
                return old.snapshot
            }
            throw error
        }
    }

    public func attribution() async -> WeatherCredit? {
        if settings.current().isOn { return await source.attribution() }
        return await whenOff?.attribution()
    }

    /// Where to ask about: her rounded position when she allowed it, else her city.
    private func coordinate(for choice: WeatherSettings) async -> CoarseCoordinate? {
        if choice.usesMyLocation, await location.access() == .allowed {
            let time = now()
            if let last = lastLocation, time.timeIntervalSince(last.at) < Self.locationLifetime {
                return last.coordinate
            }
            if let found = try? await location.currentLocation() {
                lastLocation = (found, time)
                return found
            }
        }
        lastLocation = nil
        return choice.city?.coordinate
    }

    static func hour(of date: Date) -> Int { Int(date.timeIntervalSince1970 / 3600) }
}
