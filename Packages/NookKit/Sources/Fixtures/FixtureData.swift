import Foundation
import Models

/// The records in one fixture set, before they go into the in-memory stores.
///
/// Everything is synthetic. No real photos, and no body or health details (DATA_MAP.md:
/// fixtures use synthetic garments only). Dates are relative to `now`, so "Last worn" and
/// Recently deleted read naturally whenever the app runs, and tests pass a fixed date.
public struct FixtureData: Sendable {
    public var garments: [Garment]
    public var looks: [Look]
    public var suitcases: [Suitcase]
    public var profile: Profile
    public var weather: WeatherSnapshot

    public init(
        garments: [Garment],
        looks: [Look],
        suitcases: [Suitcase],
        profile: Profile,
        weather: WeatherSnapshot
    ) {
        self.garments = garments
        self.looks = looks
        self.suitcases = suitcases
        self.profile = profile
        self.weather = weather
    }
}

extension FixtureSet {
    /// The records for this set.
    public func data(now: Date, calendar: Calendar) -> FixtureData {
        switch self {
        case .demo: DemoCloset.make(now: now, calendar: calendar)
        case .empty: EmptyCloset.make(now: now)
        case .large: LargeCloset.make(now: now, calendar: calendar)
        }
    }
}

/// "58° and rain", the weather the mockups show.
enum FixtureWeather {
    static func rainyDay(at date: Date) -> WeatherSnapshot {
        WeatherSnapshot(condition: .rain, temperatureCelsius: 14.5, isNight: false, observedAt: date)
    }
}

/// A fresh install.
enum EmptyCloset {
    static func make(now: Date) -> FixtureData {
        FixtureData(
            garments: [], looks: [], suitcases: [], profile: Profile(), weather: FixtureWeather.rainyDay(at: now))
    }
}

extension Calendar {
    /// The same time of day, `offset` days from `date`.
    func day(_ offset: Int, from date: Date) -> Date {
        self.date(byAdding: .day, value: offset, to: date) ?? date.addingTimeInterval(Double(offset) * 86_400)
    }
}
