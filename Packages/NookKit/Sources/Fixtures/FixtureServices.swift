import Foundation
import Models

/// Builds the app's services from a fixture set and a behaviour.
public enum FixtureServices {
    /// Services for a launch argument such as `-fixtures demo:offline`.
    public static func make(
        _ configuration: FixtureConfiguration,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NookServices {
        make(
            set: configuration.set,
            behavior: configuration.behavior,
            weather: configuration.weather,
            laundry: configuration.laundry,
            now: now,
            calendar: calendar
        )
    }

    /// Services filled with `set`, behaving as `behavior` says. `weather` and `laundry` force
    /// the weather service and the closet's laundry into one state; `nil` keeps the set's own.
    public static func make(
        set: FixtureSet,
        behavior: FixtureBehavior = .normal,
        weather: FixtureWeatherState? = nil,
        laundry: FixtureLaundryState? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NookServices {
        var data = set.data(now: now, calendar: calendar)
        if let laundry {
            data = data.applying(laundry: laundry)
        }
        // `unavailable` has no snapshot: the provider throws instead, so any snapshot will do.
        let snapshot = weather.flatMap { FixtureWeather.snapshot($0, at: now) } ?? data.weather
        let slow = behavior == .slow
        let stores = StoreOptions(latency: slow ? .milliseconds(600) : .zero, fails: behavior == .storesFail)

        let stylistMode: MockStylist.Mode
        switch behavior {
        case .offline: stylistMode = .failing(.offline)
        case .stylistFails: stylistMode = .failing(.notCompleted)
        case .stylistPartial: stylistMode = .partial
        case .normal, .slow, .storesFail: stylistMode = .normal
        }

        return NookServices(
            closet: InMemoryClosetStore(garments: data.garments, calendar: calendar, options: stores),
            looks: InMemoryLookStore(looks: data.looks, calendar: calendar, options: stores),
            suitcases: InMemorySuitcaseStore(suitcases: data.suitcases, options: stores),
            profile: InMemoryProfileStore(profile: data.profile, options: stores),
            stylist: MockStylist(mode: stylistMode, latency: slow ? .seconds(3) : .zero),
            weather: FixtureWeatherProvider(
                snapshot: snapshot,
                isOffline: behavior == .offline || weather == .unavailable,
                latency: slow ? .seconds(1) : .zero
            ),
            images: PlaceholderImageProvider()
        )
    }
}
