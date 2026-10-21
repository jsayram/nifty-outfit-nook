import Fixtures
import Foundation
import Models
import Services

/// The weather the app uses (Phase 29): live from Apple WeatherKit once the build says its
/// capability exists, and a stand-in until then. See `docs/weather.md` for the switch.
///
/// Either way the same chain runs: her choices (`WeatherSettings`), a city or her approximate
/// location, a forecast per place and hour, and the credit. Only the forecast source differs.
nonisolated enum AppWeather {
    /// `NOOK_WEATHERKIT = YES` in the build settings (Configs/Base.xcconfig) puts this in Info.plist.
    static let weatherKitEnabled = Bundle.main.object(forInfoDictionaryKey: "NookWeatherKitEnabled") as? String == "YES"

    /// One location manager for the app, made when first needed.
    private static let location: any ApproximateLocationProvider = CoreLocationApproximateProvider()

    /// Fills in the weather parts of `services`, which arrive with the sample weather in `weather`.
    ///
    /// - Parameter keepsSettings: whether her choices are kept on the iPhone. The debug sample
    ///   closet that UI tests open keeps nothing, so no test sees another's choices.
    static func install(into services: inout NookServices, arguments: [String], keepsSettings: Bool = true) {
        let sample = services.weather
        let settings: any WeatherSettingsStore =
            keepsSettings && !keepsNothing(arguments) ? DefaultsWeatherSettingsStore() : InMemoryWeatherSettingsStore()
        services.weatherSettings = settings
        services.cities = cities(arguments: arguments)
        services.location = locationProvider(arguments: arguments)
        if weatherKitEnabled {
            services.usesSampleWeather = false
            services.weather = PlaceWeatherProvider(
                settings: settings, location: services.location, source: WeatherKitForecastSource())
        } else {
            // Made-up weather, whatever the place. Switched off, the sample weather shows as it did
            // before Phase 29, so nothing looks different until Jose turns WeatherKit on.
            services.usesSampleWeather = true
            services.weather = PlaceWeatherProvider(
                settings: settings, location: services.location,
                source: FixtureForecastSource(standingIn: sample, credit: sampleCredit), whenOff: sample)
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// `-weather-settings-memory` (debug builds only) keeps her weather choices in memory, so UI
    /// tests start from the same choices every time.
    private static func keepsNothing(_ arguments: [String]) -> Bool {
        #if DEBUG
            arguments.contains("-weather-settings-memory")
        #else
            false
        #endif
    }

    /// Apple's credit isn't owed for made-up weather. Debug builds show it anyway, so the credit
    /// can be seen and tested.
    private static var sampleCredit: WeatherCredit? {
        #if DEBUG
            WeatherCredit()
        #else
            nil
        #endif
    }

    private static func cities(arguments: [String]) -> any CityFinder {
        #if DEBUG
            // `-weather-cities fixture|offline` (debug builds only) searches a short fixed list, so
            // UI tests don't depend on the network. Without it, Apple Maps answers.
            switch value(after: "-weather-cities", in: arguments) {
            case "fixture": return FixtureCityFinder()
            case "offline": return FixtureCityFinder(isOffline: true)
            default: break
            }
        #endif
        return MapKitCityFinder()
    }

    private static func locationProvider(arguments: [String]) -> any ApproximateLocationProvider {
        #if DEBUG
            // `-weather-location allowed|denied|ask|askDeny` (debug builds only) scripts the
            // permission, so UI tests don't have to answer iOS's alert. Without it, iOS answers.
            let seattle = CoarseCoordinate(latitude: 47.6062, longitude: -122.3321)
            switch value(after: "-weather-location", in: arguments) {
            case "allowed": return FixtureLocationProvider(access: .allowed, location: seattle)
            case "denied": return FixtureLocationProvider(access: .denied)
            case "ask": return FixtureLocationProvider(access: .notDetermined, location: seattle, grantsWhenAsked: true)
            case "askDeny":
                return FixtureLocationProvider(access: .notDetermined, location: seattle, grantsWhenAsked: false)
            default: break
            }
        #endif
        return location
    }
}
