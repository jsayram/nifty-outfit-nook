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
            draft: configuration.draft,
            photos: configuration.photos,
            now: now,
            calendar: calendar
        )
    }

    /// Services filled with `set`, behaving as `behavior` says. `weather` and `laundry` force
    /// the weather service and the closet's laundry into one state; `nil` keeps the set's own.
    /// `draft` puts an unsaved Add a piece, Edit or Make your own look draft in its store. `photos` adds the
    /// sample photo pieces and the provider that draws their pictures.
    public static func make(
        set: FixtureSet,
        behavior: FixtureBehavior = .normal,
        weather: FixtureWeatherState? = nil,
        laundry: FixtureLaundryState? = nil,
        draft: FixtureDraftState? = nil,
        photos: FixturePhotoState = .drawn,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NookServices {
        var data = set.data(now: now, calendar: calendar)
        if photos == .samples {
            data.garments = SamplePhotoGarments.garments(now: now) + data.garments
        }
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
        case .offlineOnce: stylistMode = .failingOnce(.offline)
        case .stylistFails: stylistMode = .failing(.notCompleted)
        case .stylistPartial: stylistMode = .partial
        case .stylistInsufficient: stylistMode = .insufficient
        case .normal, .slow, .stylistWaits, .storesFail, .photoFails, .pictureFails: stylistMode = .normal
        }
        let tryOnMode: SimulatedTryOn.Mode =
            switch behavior {
            case .offline: .failing(.offline)
            case .pictureFails: .failing(.notCompleted)
            default: .normal
            }
        let stylistLatency: Duration =
            switch behavior {
            case .slow: .seconds(3)
            // Long enough that only cancelling ends it.
            case .stylistWaits: .seconds(3600)
            default: .zero
            }
        let drafts = draft.flatMap { FixtureDrafts.draft($0, in: data, now: now) }.map { [$0] } ?? []
        let lookDraft = draft == .look ? FixtureDrafts.lookDraft(in: data, now: now) : nil

        return NookServices(
            closet: InMemoryClosetStore(garments: data.garments, calendar: calendar, options: stores),
            looks: InMemoryLookStore(looks: data.looks, calendar: calendar, options: stores),
            suitcases: InMemorySuitcaseStore(suitcases: data.suitcases, options: stores),
            profile: InMemoryProfileStore(profile: data.profile, options: stores),
            stylist: MockStylist(mode: stylistMode, latency: stylistLatency),
            weather: FixtureWeatherProvider(
                snapshot: snapshot,
                isOffline: behavior == .offline || weather == .unavailable,
                latency: slow ? .seconds(1) : .zero
            ),
            images: photos == .samples ? SamplePhotoProvider() : PlaceholderImageProvider(),
            drafts: InMemoryDraftStore(drafts: drafts, options: stores),
            photos: StandInPhotoIntake(fails: behavior == .photoFails, latency: slow ? .seconds(1) : .zero),
            descriptions: WordMatchDescriptionReader(latency: slow ? .seconds(1) : .zero),
            cutouts: StandInCutoutService(latency: slow ? .seconds(1) : .zero),
            lookDrafts: InMemoryLookDraftStore(draft: lookDraft, options: stores),
            pictures: InMemoryTryOnPictureStore(pictures: data.pictures, options: stores),
            // A moment, so the making state shows; a real picture takes much longer (Phase 33).
            tryOn: SimulatedTryOn(mode: tryOnMode, latency: slow ? .seconds(3) : .milliseconds(800))
        )
    }
}
