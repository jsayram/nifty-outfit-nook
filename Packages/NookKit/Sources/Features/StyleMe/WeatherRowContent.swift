import Foundation
import Models

/// Where the weather service has got to.
nonisolated enum WeatherReading: Hashable, Sendable {
    case loading
    case loaded(WeatherSnapshot)
    /// It couldn't be read (offline, or no weather service). Styling still works (LR-04.3).
    case unavailable

    var snapshot: WeatherSnapshot? {
        if case .loaded(let snapshot) = self { return snapshot }
        return nil
    }
}

/// What Style Me's Weather row and its sheet say (LR-04): "Weather · 58° and rain", with
/// "Your looks are picked for today's weather." under it, or what she chose instead.
nonisolated struct WeatherRowContent: Hashable, Sendable {
    var choice: WeatherChoice
    var reading: WeatherReading
    var locale: Locale = .current

    /// The value at the end of the row. `nil` while the weather loads; the row then shows
    /// `todayDetail` ("Checking the weather…").
    var value: String? {
        switch choice {
        case .useToday:
            switch reading {
            case .loading: return nil
            case .loaded(let snapshot): return WeatherWords.summary(snapshot, locale: locale)
            case .unavailable:
                return String(
                    localized: "Not available", bundle: .module,
                    comment: "Weather row value when the weather can't be read")
            }
        case .indoors:
            return String(localized: "Indoors", bundle: .module, comment: "Weather row value: she'll be indoors")
        case .ignore:
            return String(localized: "Ignored", bundle: .module, comment: "Weather row value: ignore the weather")
        }
    }

    /// The short line under the row, saying what the choice means for her looks.
    var explanation: String {
        switch choice {
        case .useToday:
            guard reading != .unavailable else {
                return String(
                    localized: "The weather can’t be read right now, so your looks won’t use it.", bundle: .module,
                    comment: "Under the Weather row when the weather can't be read")
            }
            return String(
                localized: "Your looks are picked for today’s weather.", bundle: .module,
                comment: "Under the Weather row")
        case .indoors:
            return String(
                localized: "Your looks are picked for a day indoors.", bundle: .module,
                comment: "Under the Weather row when she'll be indoors")
        case .ignore:
            return String(
                localized: "Your looks don’t use the weather.", bundle: .module,
                comment: "Under the Weather row when she ignores the weather")
        }
    }

    /// The row's icon: today's weather, a house for indoors, or a crossed-out circle.
    var systemImage: String {
        switch choice {
        case .useToday: reading.snapshot.map(WeatherWords.systemImage) ?? "cloud"
        case .indoors: "house"
        case .ignore: "circle.slash"
        }
    }

    /// What the "Use today's weather" option says under its title in the sheet.
    var todayDetail: String {
        switch reading {
        case .loading:
            String(localized: "Checking the weather…", bundle: .module, comment: "Weather sheet, while it loads")
        case .loaded(let snapshot):
            WeatherWords.summary(snapshot, locale: locale)
        case .unavailable:
            String(
                localized: "Can’t be read right now", bundle: .module,
                comment: "Weather sheet, when the weather can't be read")
        }
    }
}

extension WeatherChoice {
    /// The option's name in the Weather sheet (LR-04).
    nonisolated var title: String {
        switch self {
        case .useToday:
            String(localized: "Use today’s weather", bundle: .module, comment: "Weather sheet option")
        case .indoors:
            String(localized: "I’ll be indoors", bundle: .module, comment: "Weather sheet option")
        case .ignore:
            String(localized: "Ignore the weather", bundle: .module, comment: "Weather sheet option")
        }
    }

    /// A stable name for UI tests.
    nonisolated var identifier: String { "weather.\(rawValue)" }
}

/// Weather in words: "58° and rain", "72° and sunny", "61° and clear" at night.
nonisolated enum WeatherWords {
    /// The temperature in her locale's unit, rounded, as a weather app writes it ("58°").
    static func temperature(_ snapshot: WeatherSnapshot, locale: Locale) -> String {
        Measurement(value: snapshot.temperatureCelsius, unit: UnitTemperature.celsius)
            .formatted(
                .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
                    .locale(locale))
    }

    static func condition(_ snapshot: WeatherSnapshot) -> String {
        switch snapshot.condition {
        case .sun:
            snapshot.isNight
                ? String(
                    localized: "clear", bundle: .module, comment: "Weather at night with no clouds, as in 61° and clear"
                )
                : String(localized: "sunny", bundle: .module, comment: "Weather, as in 72° and sunny")
        case .cloudy: String(localized: "cloudy", bundle: .module, comment: "Weather, as in 63° and cloudy")
        case .rain: String(localized: "rain", bundle: .module, comment: "Weather, as in 58° and rain")
        case .snow: String(localized: "snow", bundle: .module, comment: "Weather, as in 30° and snow")
        }
    }

    /// "58° and rain".
    static func summary(_ snapshot: WeatherSnapshot, locale: Locale) -> String {
        let temperature = temperature(snapshot, locale: locale)
        let condition = condition(snapshot)
        return String(
            localized: "\(temperature) and \(condition)", bundle: .module,
            comment: "Today's weather: a temperature and a condition, as in 58° and rain")
    }

    static func systemImage(_ snapshot: WeatherSnapshot) -> String {
        if snapshot.isNight {
            return snapshot.condition == .sun ? "moon.stars" : "cloud.moon"
        }
        return switch snapshot.condition {
        case .sun: "sun.max"
        case .cloudy: "cloud"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        }
    }
}
