import Fixtures
import Foundation
import Models
import Synchronization
import Testing

/// Phase 29: the weather chain with stand-ins for Apple's parts: her choices, a city or her
/// approximate location, the cache per place and hour, offline and stale forecasts.
struct PlaceWeatherProviderTests {
    private static let seattle = WeatherPlace(name: "Seattle, WA", coordinate: .init(latitude: 47.6, longitude: -122.3)!)!
    private static let chicago = WeatherPlace(name: "Chicago, IL", coordinate: .init(latitude: 41.9, longitude: -87.6)!)!
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func snapshot(_ condition: WeatherCondition = .rain) -> WeatherSnapshot {
        WeatherSnapshot(condition: condition, temperatureCelsius: 14, observedAt: start)
    }

    /// A clock the test moves.
    private final class Clock: Sendable {
        private let time = Mutex(PlaceWeatherProviderTests.start)
        var now: Date { time.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { time.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    /// A source whose answers the test scripts. It counts every ask.
    private final class Source: WeatherForecastSource {
        private struct State {
            var asked: [CoarseCoordinate] = []
            var fails = false
            var condition = WeatherCondition.rain
        }
        private let state = Mutex(State())
        var asked: [CoarseCoordinate] { state.withLock { $0.asked } }
        func fail(_ fails: Bool) { state.withLock { $0.fails = fails } }
        func answer(_ condition: WeatherCondition) { state.withLock { $0.condition = condition } }

        func forecast(at coordinate: CoarseCoordinate, now: Date) async throws(WeatherError) -> WeatherSnapshot {
            let (fails, condition) = state.withLock {
                $0.asked.append(coordinate)
                return ($0.fails, $0.condition)
            }
            if fails { throw .unavailable }
            return WeatherSnapshot(condition: condition, temperatureCelsius: 14, observedAt: now)
        }
        func attribution() async -> WeatherCredit? { WeatherCredit() }
    }

    private struct Setup {
        let provider: PlaceWeatherProvider
        let settings: InMemoryWeatherSettingsStore
        let source: Source
        let location: FixtureLocationProvider
        let clock: Clock
    }

    private func make(
        _ settings: WeatherSettings, access: LocationAccess = .allowed, whenOff: (any WeatherProvider)? = nil
    ) -> Setup {
        let store = InMemoryWeatherSettingsStore(settings)
        let source = Source()
        let location = FixtureLocationProvider(
            access: access, location: .init(latitude: 40.7128, longitude: -74.0060))
        let clock = Clock()
        let provider = PlaceWeatherProvider(
            settings: store, location: location, source: source, whenOff: whenOff, now: { clock.now })
        return Setup(provider: provider, settings: store, source: source, location: location, clock: clock)
    }

    // MARK: Off and unset

    @Test func offAndNoStandInIsUnavailable() async {
        let setup = make(.off)
        await #expect(throws: WeatherError.unavailable) { try await setup.provider.currentWeather() }
        #expect(setup.source.asked.isEmpty)
    }

    @Test func offUsesTheStandInWhenThereIsOne() async throws {
        let stand = FixtureWeatherProvider(snapshot: Self.snapshot(.snow))
        let setup = make(.off, whenOff: stand)
        #expect(try await setup.provider.currentWeather().condition == .snow)
        #expect(setup.source.asked.isEmpty)
    }

    @Test func onWithNoPlaceIsUnavailable() async {
        let setup = make(WeatherSettings(isOn: true))
        await #expect(throws: WeatherError.unavailable) { try await setup.provider.currentWeather() }
        #expect(setup.source.asked.isEmpty)
    }

    // MARK: A city, with no permission

    @Test func aCityNeedsNoLocationPermission() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle), access: .denied)
        _ = try await setup.provider.currentWeather()
        #expect(setup.source.asked == [Self.seattle.coordinate])
    }

    // MARK: Her location

    @Test func approximateLocationIsAskedAboutAsRounded() async throws {
        let setup = make(WeatherSettings(isOn: true, usesMyLocation: true, city: Self.seattle))
        _ = try await setup.provider.currentWeather()
        #expect(setup.source.asked == [CoarseCoordinate(latitude: 40.7, longitude: -74.0)!])
    }

    @Test(arguments: [LocationAccess.denied, .notDetermined])
    func withoutPermissionItFallsBackToTheCity(access: LocationAccess) async throws {
        let setup = make(WeatherSettings(isOn: true, usesMyLocation: true, city: Self.seattle), access: access)
        _ = try await setup.provider.currentWeather()
        #expect(setup.source.asked == [Self.seattle.coordinate])
    }

    @Test func withoutPermissionAndWithoutACityItIsUnavailable() async {
        let setup = make(WeatherSettings(isOn: true, usesMyLocation: true), access: .denied)
        await #expect(throws: WeatherError.unavailable) { try await setup.provider.currentWeather() }
    }

    @Test func permissionTakenAwayLaterFallsBackToTheCity() async throws {
        let setup = make(WeatherSettings(isOn: true, usesMyLocation: true, city: Self.seattle))
        _ = try await setup.provider.currentWeather()
        setup.location.setAccess(.denied)
        setup.clock.advance(3600)
        _ = try await setup.provider.currentWeather()
        #expect(setup.source.asked.last == Self.seattle.coordinate)
    }

    // MARK: The cache

    @Test func oneAskPerPlaceAndHour() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        for _ in 0..<5 { _ = try await setup.provider.currentWeather() }
        setup.clock.advance(60)
        _ = try await setup.provider.currentWeather()
        #expect(setup.source.asked.count == 1)
        #expect(await setup.provider.fetchCount == 1)
    }

    @Test func aNewHourAsksAgain() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        _ = try await setup.provider.currentWeather()
        setup.source.answer(.sun)
        setup.clock.advance(3600)
        #expect(try await setup.provider.currentWeather().condition == .sun)
        #expect(setup.source.asked.count == 2)
    }

    @Test func aDifferentPlaceAsksSeparately() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        _ = try await setup.provider.currentWeather()
        setup.settings.save(WeatherSettings(isOn: true, city: Self.chicago))
        _ = try await setup.provider.currentWeather()
        setup.settings.save(WeatherSettings(isOn: true, city: Self.seattle))
        _ = try await setup.provider.currentWeather()
        #expect(setup.source.asked == [Self.seattle.coordinate, Self.chicago.coordinate])
    }

    @Test func manyAtOnceShareOneAsk() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try? await setup.provider.currentWeather() } }
        }
        #expect(setup.source.asked.count == 1)
    }

    // MARK: Offline and stale

    @Test func offlineWithNothingKeptIsUnavailable() async {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        setup.source.fail(true)
        await #expect(throws: WeatherError.unavailable) { try await setup.provider.currentWeather() }
    }

    @Test func offlineLaterUsesTheLastForecastForAWhile() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        _ = try await setup.provider.currentWeather()
        setup.source.fail(true)
        setup.clock.advance(3600)
        #expect(try await setup.provider.currentWeather().condition == .rain)
        setup.clock.advance(3600)
        #expect(try await setup.provider.currentWeather().condition == .rain)
    }

    @Test func aForecastTooOldIsNotUsed() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        _ = try await setup.provider.currentWeather()
        setup.source.fail(true)
        setup.clock.advance(PlaceWeatherProvider.staleLimit + 60)
        await #expect(throws: WeatherError.unavailable) { try await setup.provider.currentWeather() }
    }

    @Test func aFailedAskIsNotCachedAsAnAnswer() async throws {
        let setup = make(WeatherSettings(isOn: true, city: Self.seattle))
        setup.source.fail(true)
        _ = try? await setup.provider.currentWeather()
        setup.source.fail(false)
        #expect(try await setup.provider.currentWeather().condition == .rain)
    }

    // MARK: The credit

    @Test func theCreditComesFromTheSourceWhileOn() async {
        let on = make(WeatherSettings(isOn: true, city: Self.seattle))
        #expect(await on.provider.attribution() != nil)
        let off = make(.off)
        #expect(await off.provider.attribution() == nil)
    }

    // MARK: The stand-ins

    @Test func fixtureCitySearch() async throws {
        let finder = FixtureCityFinder()
        #expect(try await finder.cities(matching: "sea").map(\.name) == ["Seattle, WA"])
        #expect(try await finder.cities(matching: "x").isEmpty)
        #expect(try await finder.cities(matching: "zzzz").isEmpty)
        await #expect(throws: WeatherError.unavailable) { try await FixtureCityFinder(isOffline: true).cities(matching: "sea") }
    }

    @Test func fixtureLocationAnswersAsScripted() async {
        let yes = FixtureLocationProvider(access: .notDetermined, grantsWhenAsked: true)
        #expect(await yes.requestAccess() == .allowed)
        let no = FixtureLocationProvider(access: .notDetermined, grantsWhenAsked: false)
        #expect(await no.requestAccess() == .denied)
        await #expect(throws: WeatherError.unavailable) { try await no.currentLocation() }
    }
}
