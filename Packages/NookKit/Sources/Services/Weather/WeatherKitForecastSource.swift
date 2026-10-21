import CoreLocation
import Foundation
import Models
import Synchronization
import WeatherKit

/// Today's forecast from Apple WeatherKit (Phase 29).
///
/// Used only when the build says the WeatherKit capability exists (`NOOK_WEATHERKIT = YES`, see
/// `docs/weather.md`). Until then nothing here runs. The only thing sent to Apple is the
/// rounded coordinate this is given, which WeatherKit needs by its nature; nothing from our side
/// goes to the backend or to the stylist. A failure of any kind (no capability, offline, over
/// Apple's limit) is the same `unavailable`, so the app never shows an error for it.
public final class WeatherKitForecastSource: WeatherForecastSource {
    private let credit = Mutex<WeatherCredit?>(nil)

    public init() {}

    public func forecast(at coordinate: CoarseCoordinate, now: Date) async throws(Models.WeatherError) -> WeatherSnapshot {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let (current, daily) = try await WeatherService.shared.weather(for: location, including: .current, .daily)
            let today = daily.forecast.first
            return WeatherSnapshot(
                condition: Self.condition(current.condition),
                temperatureCelsius: current.temperature.converted(to: .celsius).value,
                isNight: !current.isDaylight,
                observedAt: now,
                lowCelsius: today?.lowTemperature.converted(to: .celsius).value,
                highCelsius: today?.highTemperature.converted(to: .celsius).value,
                precipitationChance: today?.precipitationChance)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unavailable
        }
    }

    public func attribution() async -> WeatherCredit? {
        if let known = credit.withLock({ $0 }) { return known }
        let fetched: WeatherCredit
        do {
            let attribution = try await WeatherService.shared.attribution
            fetched = WeatherCredit(
                serviceName: attribution.serviceName, markLightURL: attribution.combinedMarkLightURL,
                markDarkURL: attribution.combinedMarkDarkURL, legalURL: attribution.legalPageURL)
        } catch {
            // The credit is still owed when the service can't be asked: Apple's name and its
            // published legal page. Not remembered, so the next ask tries again for the marks.
            return WeatherCredit()
        }
        credit.withLock { $0 = fetched }
        return fetched
    }

    /// WeatherKit has 30 conditions and the Home window has four. Anything wet is rain, anything
    /// frozen is snow, clear and mostly clear are sun, and the rest (fog, haze, wind) is cloudy.
    static func condition(_ condition: WeatherKit.WeatherCondition) -> Models.WeatherCondition {
        switch condition {
        case .clear, .mostlyClear, .partlyCloudy, .hot, .breezy, .sunShowers:
            condition == .sunShowers ? .rain : .sun
        case .drizzle, .rain, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms,
            .thunderstorms, .hail, .freezingDrizzle, .freezingRain, .tropicalStorm, .hurricane:
            .rain
        case .snow, .heavySnow, .flurries, .blizzard, .blowingSnow, .sleet, .wintryMix, .sunFlurries:
            .snow
        case .cloudy, .mostlyCloudy, .foggy, .haze, .smoky, .windy, .blowingDust, .frigid:
            .cloudy
        @unknown default:
            .cloudy
        }
    }
}
