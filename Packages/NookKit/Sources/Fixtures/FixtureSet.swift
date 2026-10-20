/// The sample data set the app runs on during Stage A.
///
/// UI tests choose one with a launch argument, for example `-fixtures empty`. Options can follow
/// after colons, for example `-fixtures demo:offline` or `-fixtures demo:weather=snow:laundry=full`
/// (see `FixtureConfiguration`).
public enum FixtureSet: String, CaseIterable, Sendable {
    /// The demo closet: 21 garments, a few looks, six suitcases and a profile named Lily.
    case demo
    /// A fresh install: no garments, looks or suitcases, and default preferences.
    case empty
    /// A generated closet with more than 2,000 garments, many looks and suitcases.
    case large

    #if DEBUG
        /// The launch argument that names a fixture set.
        public static let launchArgument = "-fixtures"

        /// Reads the set from `-fixtures <name>[:<option>]...` in the launch arguments.
        ///
        /// A missing flag, a missing value or an unknown name all give `.demo`.
        public init(launchArguments: [String]) {
            self = FixtureConfiguration(launchArguments: launchArguments).set
        }
    #endif
}

/// How the fixture services behave, for loading, error and offline states.
public enum FixtureBehavior: String, CaseIterable, Sendable {
    /// Everything answers at once and works.
    case normal
    /// Every call waits: stores about half a second, weather a second, the stylist a few seconds.
    case slow
    /// No connection: the stylist and Try it on throw `offline`, and the weather can't be read.
    /// Local stores work.
    case offline
    /// The stylist runs but doesn't finish (`StylistError.notCompleted`).
    case stylistFails = "stylist-fails"
    /// The stylist returns two versions instead of three.
    case stylistPartial = "stylist-partial"
    /// The stylist says the source can't make a look (Phase 10b).
    case stylistInsufficient = "stylist-insufficient"
    /// The stylist never answers until it's cancelled, so Your looks stays on its styling
    /// state (Phase 10b).
    case stylistWaits = "stylist-waits"
    /// The stylist is offline for the first request only, so Retry works, as if the
    /// connection came back (Phase 10b). Weather and stores work.
    case offlineOnce = "offline-once"
    /// Every store call fails with `StoreError.unavailable`, for error states.
    case storesFail = "stores-fail"
    /// The Add a piece photo stand-in says the photo couldn't be read (Phase 7b).
    case photoFails = "photo-fails"
    /// Try it on doesn't finish (`TryOnError.notCompleted`, Phase 12b).
    case pictureFails = "picture-fails"
}

/// The weather the fixture weather service reports, to force each Home window (RD-01.4).
public enum FixtureWeatherState: String, CaseIterable, Sendable {
    /// 72°F and sunny.
    case sun
    /// 63°F and cloudy.
    case cloudy
    /// 58°F and rain, the mockups' weather and every set's default.
    case rain
    /// 30°F and snow.
    case snow
    /// 61°F and clear, after dark.
    case night
    /// The weather can't be read, but everything else works (LR-04.3).
    case unavailable
}

/// The laundry the fixture closet has, to force each hamper (RD-11).
public enum FixtureLaundryState: String, CaseIterable, Sendable {
    /// Tracking off. Dirty marks are kept.
    case off
    /// Tracking on, nothing dirty.
    case clean
    /// Tracking on, two pieces dirty.
    case some
    /// Tracking on, eight pieces dirty.
    case full
}

/// The source Style Me remembers at launch (Phase 13, FR-67), to show Home's suitcase and
/// Suitcases with a suitcase chosen.
public enum FixtureSourceState: String, CaseIterable, Sendable {
    /// The main closet, every set's default.
    case main
    /// Her most recently used suitcase that isn't archived ("Jose's house" in the demo).
    case suitcase
}

/// An unsaved draft waiting at launch, as if the app had been closed in the middle of Add a piece
/// or Edit (Phase 7b), or Make your own look (Phase 11). Stage A keeps drafts in memory only,
/// so UI tests use this to check what she sees after a relaunch.
public enum FixtureDraftState: String, CaseIterable, Sendable {
    /// A new piece described in words, on the details step: "Sage cardigan".
    case add
    /// Changes to the navy dress pants: renamed "Navy work trousers". Demo set only.
    case edit
    /// A half-built Make your own look (Phase 11, LR-08.4): the pink shirt and the navy dress
    /// pants, named "Pink for Friday". Demo set only.
    case look
}

/// Garment pictures in the fixture closet (Phase 8b).
public enum FixturePhotoState: String, CaseIterable, Sendable {
    /// Pieces with a photo show the sample wardrobe's real photo, or its cutout as a sticker, and
    /// pieces without one show their drawing, the default (`SampleWardrobe`).
    case real
    /// Every piece shows its drawing, as the app did before the sample wardrobe.
    case drawn
    /// `real`, plus eight more pieces with drawn sample photos and stand-in cutouts, six shown as
    /// stickers and two as photo tiles (`SamplePhotoGarments`).
    case samples
}

/// How much clothing the demo set has.
public enum FixtureWardrobeState: String, CaseIterable, Sendable {
    /// The demo closet's 21 pieces, the default.
    case demo
    /// The demo closet plus 30 more pieces with real photos, one or more of every kind in the
    /// app, and two more saved looks with their try-on previews. Applies to the demo set only
    /// (`SampleWardrobe`).
    case full
}

/// A fixture set plus options, as read from `-fixtures <set>[:<option>]...`.
///
/// Each option after a colon is one of:
/// - a behaviour (`FixtureBehavior`), such as `offline` or `stores-fail`;
/// - `weather=<state>` (`FixtureWeatherState`), such as `weather=snow`;
/// - `laundry=<state>` (`FixtureLaundryState`), such as `laundry=full`;
/// - `draft=<state>` (`FixtureDraftState`), such as `draft=add`;
/// - `photos=<state>` (`FixturePhotoState`), such as `photos=samples`;
/// - `wardrobe=<state>` (`FixtureWardrobeState`), such as `wardrobe=full`;
/// - `source=<state>` (`FixtureSourceState`), such as `source=suitcase`.
///
/// They can come in any order: `-fixtures demo:slow:weather=night:laundry=some`.
public struct FixtureConfiguration: Hashable, Sendable {
    public var set: FixtureSet
    public var behavior: FixtureBehavior
    /// `nil` keeps the set's own weather (rain).
    public var weather: FixtureWeatherState?
    /// `nil` keeps the set's own laundry and tracking setting.
    public var laundry: FixtureLaundryState?
    /// An unsaved draft waiting at launch. `nil` starts with none.
    public var draft: FixtureDraftState?
    /// Which pictures the closet shows, and whether drawn sample photos are added to it.
    public var photos: FixturePhotoState
    /// How much clothing the demo set has.
    public var wardrobe: FixtureWardrobeState
    /// `nil` keeps the set's own remembered source (the main closet).
    public var source: FixtureSourceState?

    public init(
        set: FixtureSet = .demo,
        behavior: FixtureBehavior = .normal,
        weather: FixtureWeatherState? = nil,
        laundry: FixtureLaundryState? = nil,
        draft: FixtureDraftState? = nil,
        photos: FixturePhotoState = .real,
        wardrobe: FixtureWardrobeState = .demo,
        source: FixtureSourceState? = nil
    ) {
        self.set = set
        self.behavior = behavior
        self.weather = weather
        self.laundry = laundry
        self.draft = draft
        self.photos = photos
        self.wardrobe = wardrobe
        self.source = source
    }

    /// Debug builds only: Release ships no sample data and no `-fixtures` argument (Phase 20a).
    #if DEBUG
        /// Unknown or missing parts fall back to `demo`, `normal`, the set's own weather and laundry,
        /// and no draft.
        public init(launchArguments: [String]) {
            guard
                let flagIndex = launchArguments.firstIndex(of: FixtureSet.launchArgument),
                launchArguments.indices.contains(flagIndex + 1)
            else {
                self.init()
                return
            }
            let parts = launchArguments[flagIndex + 1].split(separator: ":").map(String.init)
            self.init(set: parts.first.flatMap(FixtureSet.init(rawValue:)) ?? .demo)
            for option in parts.dropFirst() {
                if let behavior = FixtureBehavior(rawValue: option) {
                    self.behavior = behavior
                    continue
                }
                let pair = option.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                switch pair[0] {
                case "weather": weather = FixtureWeatherState(rawValue: pair[1]) ?? weather
                case "laundry": laundry = FixtureLaundryState(rawValue: pair[1]) ?? laundry
                case "draft": draft = FixtureDraftState(rawValue: pair[1]) ?? draft
                case "photos": photos = FixturePhotoState(rawValue: pair[1]) ?? photos
                case "wardrobe": wardrobe = FixtureWardrobeState(rawValue: pair[1]) ?? wardrobe
                case "source": source = FixtureSourceState(rawValue: pair[1]) ?? source
                default: continue
                }
            }
        }
    #endif
}
