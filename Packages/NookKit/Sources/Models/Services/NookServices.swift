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
    /// Her try-on pictures (Phase 12b).
    public var pictures: any TryOnPictureStore
    /// Try it on (simulated in Stage A; the gated image service is Phase 33).
    public var tryOn: any TryOnService
    /// Which first-use tours she has seen, and whether tours start on their own (Phase 16a).
    public var tours: any TourProgressStore
    /// Whether she has finished onboarding, and the closet she started with (Phase 17).
    public var onboarding: any OnboardingStateStore
    /// The Send feedback note she hasn't sent yet (Phase 21a).
    public var feedbackDrafts: any FeedbackDraftStore
    /// Whether what she adds and changes is kept when the app closes. True for her own closet in
    /// the store on the iPhone (Phase 21a); false for the debug sample closet, which comes back as
    /// it ships at each launch. Help and Privacy and terms say which.
    public var keepsChanges = true
    /// Export a copy, Check a copy and Restore (Phase 21b). `nil` where there's nothing to back
    /// up: the debug sample closet in memory, previews and most tests.
    public var backups: (any BackupService)?
    /// Her image files (Phase 22b): removes the ones nothing points to any more. Nothing to do
    /// where photos aren't files: the debug sample closet in memory, previews and most tests.
    public var imageFiles: any ImageFiles = NoImageFiles()
    /// Her live-weather choices (Phase 29): on or off, her city, and whether to use her
    /// approximate location. In memory until the app sets a store that keeps them.
    public var weatherSettings: any WeatherSettingsStore = InMemoryWeatherSettingsStore()
    /// True while the weather is a stand-in (made-up weather, nothing fetched), which is so until
    /// WeatherKit is switched on for the build (`docs/weather.md`). Privacy and terms says
    /// so, and Apple's credit isn't shown for it.
    public var usesSampleWeather = true
    /// Her approximate location for the weather, only if she turns it on (Phase 29).
    public var location: any ApproximateLocationProvider = UnavailableLocationProvider()
    /// Finds a city by name for the weather, with no location permission (Phase 29).
    public var cities: any CityFinder = UnavailableCityFinder()
    /// Sign in and the backend account (Phase 24a). Signed out until the app sets one: a fake
    /// sign-in and an in-process fake backend, or Clerk and Convex when they're configured.
    public var account: any AccountService = UnavailableAccountService()
    /// Paid cloud work and her allowances (Phase 24b), for the stylist (27a) and try-on (33a).
    /// Signed out until the app sets one, like `account`.
    public var paid: any PaidActionService = UnavailablePaidActionService()
    /// Send feedback's support queue (Phase 24d). Unavailable until the app sets one, and then the
    /// page uses the share sheet; signed out it says so the same way.
    public var feedback: any FeedbackService = UnavailableFeedbackService()
    /// Shrinks and cleans a screenshot she chooses for a note (Phase 24d).
    public var screenshots: any FeedbackScreenshotPreparing = UnavailableScreenshotPreparer()
    /// The website's support page (Phase 24d), a placeholder address until the page is published.
    public var supportLinks = SupportLinks()
    /// 27a: her yes to the cloud stylist's provider. Erased by Delete my data.
    public var stylistConsent: any StylistConsentStore = InMemoryStylistConsentStore()
    /// 27a: true when `stylist` is the cloud stylist. Then Style Me checks her history first
    /// (FR-58) and Privacy and terms shows the stylist's consent switch. Stage A's mock stylist
    /// sends nothing, so neither applies.
    public var cloudStyling = false
    /// Phase 28: Quick ideas, the stylist on the phone that answers when the cloud can't (no
    /// consent, offline, a limit, a failure). `nil` uses the standard one (`QuickIdeasStylist`
    /// with Features' words); tests put a scripted stylist here.
    public var quickIdeas: (any Stylist)?
    /// Phase 28: a stylist on Apple's on-device model, for iPhones with Apple Intelligence. None is
    /// built yet (`docs/decisions/0010-on-device-stylist.md`), so the router never picks that lane.
    public var onDeviceStylist: (any Stylist)?
    /// Phase 28: whether Apple's on-device model can run here. The app sets the real check.
    public var onDeviceModel: any OnDeviceModelCheck = NoOnDeviceModel()
    /// 27c: every paid AI job (Style Me's outfit ideas, Ask stylist, try-on in 33a), run apart
    /// from any screen and kept across a relaunch, with the banner and notifications that say a
    /// job is done. Copies of these services share it.
    public var aiJobs = AIJobs()
    /// 27c: Ask stylist conversations, kept so she can leave and come back.
    public var stylistThreads: any StylistThreadStore = InMemoryStylistThreadStore()
    /// Delete my data (Phase 14b). By default it erases the stores above as they are when it's
    /// read, so a store replaced after `init` is the one erased. Phase 24c adds the account and
    /// what the server holds.
    public var deletion: any DataDeletionService {
        get {
            customDeletion
                ?? LocalDataDeletion(
                    closet: closet, looks: looks, suitcases: suitcases, profile: profile, drafts: drafts,
                    lookDrafts: lookDrafts, feedbackDrafts: feedbackDrafts, pictures: pictures, tours: tours,
                    onboarding: onboarding, weatherSettings: weatherSettings, stylistConsent: stylistConsent,
                    aiJobs: AIJobsEraser(aiJobs), stylistThreads: stylistThreads)
        }
        set { customDeletion = newValue }
    }

    /// A deletion service passed in or set, instead of erasing the stores above.
    private var customDeletion: (any DataDeletionService)?

    /// - Parameter deletion: what Delete my data uses. `nil` erases every store above, which is
    ///   what Stage A and the local part of Stage B want.
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
        lookDrafts: any LookDraftStore,
        pictures: any TryOnPictureStore,
        tryOn: any TryOnService,
        tours: any TourProgressStore,
        onboarding: any OnboardingStateStore,
        feedbackDrafts: any FeedbackDraftStore,
        deletion: (any DataDeletionService)? = nil
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
        self.pictures = pictures
        self.tryOn = tryOn
        self.tours = tours
        self.onboarding = onboarding
        self.feedbackDrafts = feedbackDrafts
        self.customDeletion = deletion
    }
}
