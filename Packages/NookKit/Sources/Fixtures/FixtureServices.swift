import Foundation
import Models

/// Builds the app's services from a fixture set and a behaviour.
public enum FixtureServices {
    /// Services for a launch argument such as `-fixtures demo:offline`.
    ///
    /// - Parameters:
    ///   - startingCloset: the closet chosen in onboarding (Phase 17). `nil` uses the set the
    ///     configuration names, as it is, which is what the debug `-onboarding skip` flag and the
    ///     tests want. `.sample` is that set too (the demo set if the configuration names the
    ///     empty one), with no name on the sign: her name comes from onboarding, or from
    ///     `profileSettings`. `.empty` is the empty set with the configuration's other options.
    ///   - tours, onboarding: the stores kept across launches. `nil` gives in-memory ones that
    ///     start fresh.
    ///   - profileSettings: where the name on the sign and the Style Me settings are kept across
    ///     launches (Stage A audit). `nil` keeps the whole profile in memory.
    ///   - feedbackDrafts: where the unsent Send feedback note is kept. `nil` keeps it in memory.
    ///   - stores: the real stores on the iPhone (Phase 21a). When given, her data lives there
    ///     instead of in memory: the set's garments, looks, suitcases, pictures, profile and
    ///     drafts aren't loaded, and the store options (`slow`, `stores-fail`) and `draft=` don't
    ///     apply. The providers (stylist, weather, pictures, try-on) still follow the configuration.
    public static func make(
        _ configuration: FixtureConfiguration,
        startingCloset: StartingCloset? = nil,
        tours: (any TourProgressStore)? = nil,
        onboarding: (any OnboardingStateStore)? = nil,
        profileSettings: (any ProfileSettingsKeeper)? = nil,
        feedbackDrafts: (any FeedbackDraftStore)? = nil,
        stores: NookStoreSet? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NookServices {
        let set: FixtureSet
        switch startingCloset {
        case nil: set = configuration.set
        case .sample: set = configuration.set == .empty ? .demo : configuration.set
        case .empty: set = .empty
        }
        return make(
            set: set,
            behavior: configuration.behavior,
            weather: configuration.weather,
            laundry: configuration.laundry,
            draft: configuration.draft,
            photos: startingCloset == .empty ? .drawn : configuration.photos,
            wardrobe: configuration.wardrobe,
            source: configuration.source,
            unnamed: startingCloset != nil,
            tours: tours,
            onboarding: onboarding,
            profileSettings: profileSettings,
            feedbackDrafts: feedbackDrafts,
            stores: stores,
            now: now,
            calendar: calendar
        )
    }

    /// Services filled with `set`, behaving as `behavior` says. `weather` and `laundry` force
    /// the weather service and the closet's laundry into one state; `nil` keeps the set's own.
    /// `draft` puts an unsaved Add a piece, Edit or Make your own look draft in its store. `photos` picks
    /// the provider of garment pictures (the sample wardrobe's photos, or none) and can add the drawn
    /// sample photo pieces. `wardrobe` adds the full wardrobe to the demo set. `source` sets the
    /// remembered source. `unnamed` leaves the sign without a name, for a closet started from
    /// onboarding. `tours` and `onboarding` are the stores to use; `nil` gives fresh in-memory ones.
    /// `profileSettings` keeps the name on the sign and the Style Me settings; with `nil` the
    /// whole profile is in memory. `feedbackDrafts` and `stores` are as above.
    public static func make(
        set: FixtureSet,
        behavior: FixtureBehavior = .normal,
        weather: FixtureWeatherState? = nil,
        laundry: FixtureLaundryState? = nil,
        draft: FixtureDraftState? = nil,
        photos: FixturePhotoState = .real,
        wardrobe: FixtureWardrobeState = .demo,
        source: FixtureSourceState? = nil,
        unnamed: Bool = false,
        tours: (any TourProgressStore)? = nil,
        onboarding: (any OnboardingStateStore)? = nil,
        profileSettings: (any ProfileSettingsKeeper)? = nil,
        feedbackDrafts: (any FeedbackDraftStore)? = nil,
        stores: NookStoreSet? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NookServices {
        var data = set.data(now: now, calendar: calendar)
            .applying(wardrobe: wardrobe, to: set, now: now, calendar: calendar)
        if unnamed {
            data.profile.signName = ""
        }
        #if DEBUG
            if photos == .samples {
                data.garments = SamplePhotoGarments.garments(now: now) + data.garments
            }
        #endif
        if let laundry {
            data = data.applying(laundry: laundry)
        }
        if let source {
            data = data.applying(source: source)
        }
        // `unavailable` has no snapshot: the provider throws instead, so any snapshot will do.
        let snapshot = weather.flatMap { FixtureWeather.snapshot($0, at: now) } ?? data.weather
        let slow = behavior == .slow
        let options = StoreOptions(latency: slow ? .milliseconds(600) : .zero, fails: behavior == .storesFail)

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
        #if DEBUG
            let drafts = draft.flatMap { FixtureDrafts.draft($0, in: data, now: now) }.map { [$0] } ?? []
            let lookDraft = draft == .look ? FixtureDrafts.lookDraft(in: data, now: now) : nil
        #else
            let drafts: [GarmentDraft] = []
            let lookDraft: LookDraft? = nil
        #endif

        let held =
            stores
            ?? NookStoreSet(
                closet: InMemoryClosetStore(garments: data.garments, calendar: calendar, options: options),
                looks: InMemoryLookStore(looks: data.looks, calendar: calendar, options: options),
                suitcases: InMemorySuitcaseStore(suitcases: data.suitcases, options: options),
                profile: profileStore(data.profile, settings: profileSettings, options: options),
                drafts: InMemoryDraftStore(drafts: drafts, options: options),
                lookDrafts: InMemoryLookDraftStore(draft: lookDraft, options: options),
                pictures: InMemoryTryOnPictureStore(pictures: data.pictures, options: options),
                feedbackDrafts: feedbackDrafts ?? InMemoryFeedbackDraftStore(options: options))
        let profile = held.profile

        var services = NookServices(
            closet: held.closet,
            looks: held.looks,
            suitcases: held.suitcases,
            profile: profile,
            stylist: MockStylist(mode: stylistMode, latency: stylistLatency),
            weather: FixtureWeatherProvider(
                snapshot: snapshot,
                isOffline: behavior == .offline || weather == .unavailable,
                latency: slow ? .seconds(1) : .zero
            ),
            images: imageProvider(for: photos),
            drafts: held.drafts,
            photos: StandInPhotoIntake(fails: behavior == .photoFails, latency: slow ? .seconds(1) : .zero),
            descriptions: WordMatchDescriptionReader(latency: slow ? .seconds(1) : .zero),
            cutouts: StandInCutoutService(latency: slow ? .seconds(1) : .zero),
            lookDrafts: held.lookDrafts,
            pictures: held.pictures,
            // A moment, so the making state shows; a real picture takes much longer (Phase 33).
            tryOn: SimulatedTryOn(
                mode: tryOnMode, latency: slow ? .seconds(3) : .milliseconds(800), usesSamplePreviews: photos != .drawn,
                hasTryOnPhoto: { (try? await profile.profile().tryOnPhoto) != nil }),
            // Every set starts as a fresh install: no tour seen, tips on (Phase 16a), unless the
            // app passes the stores it keeps across launches (Phase 17).
            tours: tours ?? InMemoryTourProgressStore(options: options),
            onboarding: onboarding ?? InMemoryOnboardingStore(options: options),
            feedbackDrafts: held.feedbackDrafts
        )
        // Sample data in memory comes back as it ships; the real stores keep her changes.
        services.keepsChanges = stores != nil
        return services
    }

    /// Garment pictures: the sample wardrobe's, plus the drawn sample photos for `samples`, or none.
    /// Release builds have no sample photos (Phase 20a), so every piece shows its drawing.
    private static func imageProvider(for photos: FixturePhotoState) -> any ImageProvider {
        #if DEBUG
            switch photos {
            case .real: SampleWardrobeProvider()
            case .samples: SampleWardrobeProvider(drawnSamples: true)
            case .drawn: PlaceholderImageProvider()
            }
        #else
            PlaceholderImageProvider()
        #endif
    }

    private static func profileStore(
        _ profile: Profile, settings: (any ProfileSettingsKeeper)?, options: StoreOptions
    ) -> any ProfileStore {
        guard let settings else { return InMemoryProfileStore(profile: profile, options: options) }
        return KeptSettingsProfileStore(profile: profile, keeper: settings) {
            InMemoryProfileStore(profile: $0, options: options)
        }
    }
}
