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
        make(set: configuration.set, behavior: configuration.behavior, now: now, calendar: calendar)
    }

    /// Services filled with `set`, behaving as `behavior` says.
    public static func make(
        set: FixtureSet,
        behavior: FixtureBehavior = .normal,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NookServices {
        let data = set.data(now: now, calendar: calendar)
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
                snapshot: data.weather,
                isOffline: behavior == .offline,
                latency: slow ? .seconds(1) : .zero
            ),
            images: PlaceholderImageProvider()
        )
    }
}
