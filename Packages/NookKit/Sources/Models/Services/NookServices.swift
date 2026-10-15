/// Every service the app uses, as protocols. The app target builds one and hands it to the
/// screens; features never create services themselves.
///
/// Stage A fills it from a fixture set (`FixtureServices` in Fixtures). Stage B swaps in real
/// stores and providers without touching any screen.
public struct NookServices: Sendable {
    public var closet: any ClosetStore
    public var looks: any LookStore
    public var suitcases: any SuitcaseStore
    public var profile: any ProfileStore
    public var stylist: any Stylist
    public var weather: any WeatherProvider
    public var images: any ImageProvider
    /// Unsaved Add a piece and Edit work (Phase 7b).
    public var drafts: any DraftStore
    /// The photo step of Add a piece (a stand-in until Phase 22a).
    public var photos: any PhotoIntake
    /// "Describe in words" suggestions (an on-phone word matcher in Stage A).
    public var descriptions: any GarmentDescriptionReader
    /// Lifting a garment out of its photo (a stand-in in Stage A; Vision is measured in Phase 8a).
    public var cutouts: any CutoutService
    /// The unsaved Make your own look draft (Phase 11, LR-08.4).
    public var lookDrafts: any LookDraftStore

    public init(
        closet: any ClosetStore,
        looks: any LookStore,
        suitcases: any SuitcaseStore,
        profile: any ProfileStore,
        stylist: any Stylist,
        weather: any WeatherProvider,
        images: any ImageProvider,
        drafts: any DraftStore,
        photos: any PhotoIntake,
        descriptions: any GarmentDescriptionReader,
        cutouts: any CutoutService,
        lookDrafts: any LookDraftStore
    ) {
        self.closet = closet
        self.looks = looks
        self.suitcases = suitcases
        self.profile = profile
        self.stylist = stylist
        self.weather = weather
        self.images = images
        self.drafts = drafts
        self.photos = photos
        self.descriptions = descriptions
        self.cutouts = cutouts
        self.lookDrafts = lookDrafts
    }
}
