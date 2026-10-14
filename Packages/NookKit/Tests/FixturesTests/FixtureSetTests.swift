import Fixtures
import Foundation
import Models
import Testing

struct FixtureSetTests {
    @Test(arguments: FixtureSet.allCases)
    func readsEachNamedSet(_ set: FixtureSet) {
        let arguments = ["NiftyOutfitNook", "-fixtures", set.rawValue]
        #expect(FixtureSet(launchArguments: arguments) == set)
    }

    @Test func defaultsToDemoWithoutTheFlag() {
        #expect(FixtureSet(launchArguments: ["NiftyOutfitNook"]) == .demo)
    }

    @Test func defaultsToDemoWhenTheValueIsMissing() {
        #expect(FixtureSet(launchArguments: ["NiftyOutfitNook", "-fixtures"]) == .demo)
    }

    @Test func defaultsToDemoForAnUnknownName() {
        #expect(FixtureSet(launchArguments: ["NiftyOutfitNook", "-fixtures", "huge"]) == .demo)
    }

    @Test func ignoresOtherArguments() {
        let arguments = ["NiftyOutfitNook", "-AppleLanguages", "(en)", "-fixtures", "large"]
        #expect(FixtureSet(launchArguments: arguments) == .large)
    }
}

struct FixtureConfigurationTests {
    @Test func readsASetAndABehavior() {
        let configuration = FixtureConfiguration(launchArguments: ["App", "-fixtures", "large:stylist-fails"])
        #expect(configuration == FixtureConfiguration(set: .large, behavior: .stylistFails))
        #expect(FixtureSet(launchArguments: ["App", "-fixtures", "empty:offline"]) == .empty)
    }

    @Test(arguments: FixtureBehavior.allCases)
    func readsEachBehavior(_ behavior: FixtureBehavior) {
        let configuration = FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:\(behavior.rawValue)"])
        #expect(configuration.behavior == behavior)
    }

    @Test func unknownPartsFallBackToDemoAndNormal() {
        #expect(FixtureConfiguration(launchArguments: ["App"]) == FixtureConfiguration())
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo"]).behavior == .normal)
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:wobbly"]).behavior == .normal)
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "huge:slow"]).set == .demo)
    }

    /// `-fixtures demo:weather=snow:laundry=full`, in any order, with or without a behaviour.
    @Test func readsWeatherAndLaundryOptions() {
        #expect(
            FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:weather=snow:laundry=full"])
                == FixtureConfiguration(set: .demo, weather: .snow, laundry: .full))
        #expect(
            FixtureConfiguration(launchArguments: ["App", "-fixtures", "empty:laundry=off:slow:weather=night"])
                == FixtureConfiguration(set: .empty, behavior: .slow, weather: .night, laundry: .off))
    }

    @Test(arguments: FixtureWeatherState.allCases)
    func readsEachWeather(_ weather: FixtureWeatherState) {
        let configuration = FixtureConfiguration(launchArguments: [
            "App", "-fixtures", "demo:weather=\(weather.rawValue)",
        ])
        #expect(configuration.weather == weather)
        #expect(configuration.behavior == .normal)
    }

    @Test(arguments: FixtureLaundryState.allCases)
    func readsEachLaundry(_ laundry: FixtureLaundryState) {
        let configuration = FixtureConfiguration(launchArguments: [
            "App", "-fixtures", "demo:laundry=\(laundry.rawValue)",
        ])
        #expect(configuration.laundry == laundry)
    }

    @Test func unknownOptionsAreIgnored() {
        let configuration = FixtureConfiguration(
            launchArguments: ["App", "-fixtures", "demo:weather=hail:laundry=:mood=sunny:offline"])
        #expect(configuration == FixtureConfiguration(set: .demo, behavior: .offline))
    }
}

/// The forced weather and laundry states reach the services (RD-01.4, RD-11).
struct FixtureStateTests {
    private func services(
        weather: FixtureWeatherState? = nil, laundry: FixtureLaundryState? = nil, set: FixtureSet = .demo
    )
        -> NookServices
    {
        FixtureServices.make(
            set: set, weather: weather, laundry: laundry, now: TestTime.now, calendar: TestTime.calendar)
    }

    @Test func eachWeatherIsReported() async throws {
        let expected: [FixtureWeatherState: (WeatherCondition, Bool)] = [
            .sun: (.sun, false), .cloudy: (.cloudy, false), .rain: (.rain, false), .snow: (.snow, false),
            .night: (.sun, true),
        ]
        for (state, (condition, isNight)) in expected {
            let weather = try await services(weather: state).weather.currentWeather()
            #expect(weather.condition == condition, "\(state)")
            #expect(weather.isNight == isNight, "\(state)")
        }
    }

    /// The mockups' temperatures: 72, 63, 58, 30 and 61 degrees Fahrenheit.
    @Test func temperaturesMatchTheMockups() async throws {
        let expected: [FixtureWeatherState: Double] = [.sun: 72, .cloudy: 63, .rain: 58, .snow: 30, .night: 61]
        for (state, fahrenheit) in expected {
            let celsius = try await services(weather: state).weather.currentWeather().temperatureCelsius
            #expect((celsius * 9 / 5 + 32).rounded() == fahrenheit, "\(state)")
        }
    }

    @Test func unavailableWeatherThrowsButTheStylistStillWorks() async throws {
        let services = services(weather: .unavailable)
        await #expect(throws: WeatherError.unavailable) { try await services.weather.currentWeather() }
        #expect(try await services.closet.garments().count > 0)
    }

    @Test func noWeatherOptionKeepsTheRainyDay() async throws {
        #expect(try await services().weather.currentWeather().condition == .rain)
    }

    @Test func laundryOffKeepsTheDirtyMarks() async throws {
        let services = services(laundry: .off)
        #expect(try await services.profile.profile().preferences.tracksLaundry == false)
        #expect(try await dirtyCount(services) == 2)
    }

    @Test(arguments: [(FixtureLaundryState.clean, 0), (.some, 2), (.full, 8)])
    func laundryOnLeavesExactlyThatManyDirty(_ state: FixtureLaundryState, dirty: Int) async throws {
        for set in [FixtureSet.demo, .large] {
            let services = services(laundry: state, set: set)
            #expect(try await services.profile.profile().preferences.tracksLaundry, "\(set)")
            #expect(try await dirtyCount(services) == dirty, "\(set)")
        }
    }

    /// An empty closet has nothing to mark, so its hamper is all clean.
    @Test func anEmptyClosetHasNothingToWash() async throws {
        let services = services(laundry: .full, set: .empty)
        #expect(try await services.profile.profile().preferences.tracksLaundry)
        #expect(try await dirtyCount(services) == 0)
    }

    private func dirtyCount(_ services: NookServices) async throws -> Int {
        try await services.closet.garments().count { $0.isInCloset && $0.laundry == .dirty }
    }
}
