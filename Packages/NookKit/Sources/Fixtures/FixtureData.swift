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
    /// Try-on pictures (Phase 12b), all Simulated: drawn from their looks' pieces, or a sample
    /// preview of the person in the example try-on photo wearing the look.
    public var pictures: [TryOnPicture]

    public init(
        garments: [Garment],
        looks: [Look],
        suitcases: [Suitcase],
        profile: Profile,
        weather: WeatherSnapshot,
        pictures: [TryOnPicture] = []
    ) {
        self.garments = garments
        self.looks = looks
        self.suitcases = suitcases
        self.profile = profile
        self.weather = weather
        self.pictures = pictures
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

/// "58° and rain", the weather the mockups show, and the other states the Home window draws.
/// The temperatures are the mockups' (`screens/home.html`), in Celsius.
enum FixtureWeather {
    static func rainyDay(at date: Date) -> WeatherSnapshot {
        WeatherSnapshot(condition: .rain, temperatureCelsius: 14.5, isNight: false, observedAt: date)
    }

    /// The snapshot for a forced state, or `nil` for `unavailable`, which has none.
    static func snapshot(_ state: FixtureWeatherState, at date: Date) -> WeatherSnapshot? {
        switch state {
        case .sun: WeatherSnapshot(condition: .sun, temperatureCelsius: 22.2, observedAt: date)
        case .cloudy: WeatherSnapshot(condition: .cloudy, temperatureCelsius: 17.2, observedAt: date)
        case .rain: rainyDay(at: date)
        case .snow: WeatherSnapshot(condition: .snow, temperatureCelsius: -1.1, observedAt: date)
        case .night: WeatherSnapshot(condition: .sun, temperatureCelsius: 16.1, isNight: true, observedAt: date)
        case .unavailable: nil
        }
    }
}

extension FixtureData {
    /// How many pieces `some` and `full` leave dirty.
    static func dirtyCount(for state: FixtureLaundryState) -> Int {
        switch state {
        case .off, .clean: 0
        case .some: 2
        case .full: 8
        }
    }

    /// The same records with laundry forced to `state`. With tracking on, exactly
    /// `dirtyCount(for:)` pieces in her closet are dirty, the set's own dirty pieces first, or
    /// fewer if the closet is smaller. With it off, the set's dirty marks are kept (RD-11).
    func applying(laundry state: FixtureLaundryState) -> FixtureData {
        var data = self
        data.profile.preferences.tracksLaundry = state != .off
        guard state != .off else { return data }
        let candidates = garments.indices.filter { garments[$0].isInCloset }
        let dirtyFirst =
            candidates.filter { garments[$0].laundry == .dirty }
            + candidates.filter { garments[$0].laundry != .dirty }
        let dirty = Set(dirtyFirst.prefix(Self.dirtyCount(for: state)))
        for index in data.garments.indices {
            data.garments[index].laundry = dirty.contains(index) ? .dirty : .clean
        }
        return data
    }
}

extension FixtureData {
    /// The same records with the remembered source set to `state`. A set with no suitcases
    /// keeps the main closet.
    func applying(source state: FixtureSourceState) -> FixtureData {
        var data = self
        switch state {
        case .main:
            data.profile.remembered.source = .mainCloset
        case .suitcase:
            if let suitcase = SuitcaseShelf(suitcases).favorites.first {
                data.profile.remembered.source = .suitcase(suitcase.id)
            }
        }
        return data
    }
}

extension FixtureData {
    /// The same records with the full wardrobe: the 30 extra pieces, and the look and try-on
    /// preview that need them (`SampleWardrobe`). Only the demo set has it, so anything else
    /// is unchanged.
    func applying(wardrobe state: FixtureWardrobeState, to set: FixtureSet, now: Date, calendar: Calendar)
        -> FixtureData
    {
        guard state == .full, set == .demo else { return self }
        var data = self
        let day = { (offset: Int) in calendar.day(offset, from: now) }
        data.garments += SampleWardrobe.extraGarments(day: day)
        let looks = SampleWardrobe.previewLooks(full: true, day: day).filter { look in
            !self.looks.contains { $0.id == look.id }
        }
        data.looks += looks
        data.pictures += SampleWardrobe.previewPictures(looks: looks, day: day)
        return data
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
