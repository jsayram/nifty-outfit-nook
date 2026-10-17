import Models

/// One tour in App tours (Phase 16b, PRD §7.8): the screen's name, how many tips and what they
/// cover.
struct TourCatalogEntry: Identifiable, Hashable, Sendable {
    let id: TourID
    let title: String
    /// What the tips are about, in a few words.
    let summary: String
    /// How many tips it has, as App tours says it. A tour about something that isn't there
    /// (Laundry's suitcase chips, Your looks' versions) can show one fewer.
    let stepCount: Int
    let systemImage: String
    /// Listed first; the rest are under More screen tours (PRD §7.8).
    let isCommon: Bool
    /// When the tour starts somewhere she has to go herself: "Shows when your looks are ready".
    var startsLater: String?

    /// "3 quick tips · Add, find and filter your clothes".
    var detail: String {
        "\(TourCatalog.quickTips(stepCount)) · \(summary)"
    }
}

/// Every tour App tours lists, in order (`settings.html?sheet=tours`): Home, Closet, Style Me,
/// Your looks, Saved Looks, Suitcases and Fit and measurements, then More screen tours. The
/// mockup's other entries are screens the app doesn't have yet (subscriptions, Find One, Ask
/// stylist, onboarding) or other layouts of Home, Closet, Your looks and Saved Looks, which
/// share their screen's tour.
nonisolated enum TourCatalog {
    static var entries: [TourCatalogEntry] {
        [
            TourCatalogEntry(
                id: .home, title: String(localized: "Home", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "The laptop, the wardrobe, the suitcase and your sign", bundle: .module,
                    comment: "App tours: what Home's tour covers"),
                stepCount: 4, systemImage: "house", isCommon: true),
            TourCatalogEntry(
                id: .closet, title: String(localized: "Closet", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Add, find and filter your clothes", bundle: .module,
                    comment: "App tours: what Closet's tour covers"),
                stepCount: 3, systemImage: "hanger", isCommon: true),
            TourCatalogEntry(
                id: .styleMe, title: String(localized: "Style Me", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Which clothes, your plans and Style me", bundle: .module,
                    comment: "App tours: what Style Me's tour covers"),
                stepCount: 3, systemImage: "sparkles", isCommon: true),
            TourCatalogEntry(
                id: .yourLooks, title: String(localized: "Your looks", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "The three versions, saving, trying on and swapping", bundle: .module,
                    comment: "App tours: what Your looks' tour covers"),
                stepCount: 4, systemImage: "sparkles", isCommon: true,
                startsLater: String(
                    localized: "Opens Style Me. Shows when your looks are ready.", bundle: .module,
                    comment: "App tours: Your looks' tour needs a Style Me request first")),
            TourCatalogEntry(
                id: .savedLooks,
                title: String(localized: "Saved Looks", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Your looks, your pictures and search", bundle: .module,
                    comment: "App tours: what Saved Looks' tour covers"),
                stepCount: 3, systemImage: "bookmark", isCommon: true),
            TourCatalogEntry(
                id: .suitcases, title: String(localized: "Suitcases", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Making a suitcase and choosing one", bundle: .module,
                    comment: "App tours: what Suitcases' tour covers"),
                stepCount: 2, systemImage: "suitcase.rolling", isCommon: true),
            TourCatalogEntry(
                id: .fit,
                title: String(localized: "Fit and measurements", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Your usual fit, measurements and pieces that fit", bundle: .module,
                    comment: "App tours: what Fit and measurements' tour covers"),
                stepCount: 4, systemImage: "ruler", isCommon: true),
            TourCatalogEntry(
                id: .swap, title: String(localized: "Swap a piece", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Changing or removing one piece", bundle: .module,
                    comment: "App tours: what Swap a piece's tour covers"),
                stepCount: 4, systemImage: "arrow.left.arrow.right", isCommon: false,
                startsLater: String(
                    localized: "Shows when you next tap Swap a piece.", bundle: .module,
                    comment: "App tours: Swap a piece's tour starts when she opens it")),
            TourCatalogEntry(
                id: .lookBuilder,
                title: String(localized: "Make your own look", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Building an outfit piece by piece", bundle: .module,
                    comment: "App tours: what Make your own look's tour covers"),
                stepCount: 3, systemImage: "square.stack", isCommon: false),
            TourCatalogEntry(
                id: .look, title: String(localized: "A saved look", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Wearing, swapping and renaming it", bundle: .module,
                    comment: "App tours: what a saved look's tour covers"),
                stepCount: 3, systemImage: "bookmark", isCommon: false),
            TourCatalogEntry(
                id: .picture,
                title: String(localized: "Try-on picture", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Its look, and deleting it", bundle: .module,
                    comment: "App tours: what a try-on picture's tour covers"),
                stepCount: 2, systemImage: "camera", isCommon: false),
            TourCatalogEntry(
                id: .tryOn, title: String(localized: "Try it on", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "What the picture is, and making it", bundle: .module,
                    comment: "App tours: what the Try it on sheet's tour covers"),
                stepCount: 2, systemImage: "camera", isCommon: false,
                startsLater: String(
                    localized: "Opens your first saved look. Shows when you tap Try it on.", bundle: .module,
                    comment: "App tours: the Try it on tour starts when she opens the sheet")),
            TourCatalogEntry(
                id: .garment,
                title: String(localized: "A piece of clothing", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Editing, styling and packing it", bundle: .module,
                    comment: "App tours: what a piece's tour covers"),
                stepCount: 3, systemImage: "tshirt", isCommon: false),
            TourCatalogEntry(
                id: .addPiece, title: String(localized: "Add a piece", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "A photo, or words", bundle: .module,
                    comment: "App tours: what Add a piece's tour covers"
                ),
                stepCount: 2, systemImage: "plus", isCommon: false),
            TourCatalogEntry(
                id: .editPiece,
                title: String(localized: "Editing a piece", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "The photo, the details and Save", bundle: .module,
                    comment: "App tours: what the Edit a piece tour covers"),
                stepCount: 3, systemImage: "pencil", isCommon: false),
            TourCatalogEntry(
                id: .recentlyDeleted,
                title: String(localized: "Recently deleted", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Bringing a piece back", bundle: .module,
                    comment: "App tours: what Recently deleted's tour covers"),
                stepCount: 2, systemImage: "trash", isCommon: false),
            TourCatalogEntry(
                id: .laundry, title: String(localized: "Laundry", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Marking pieces clean", bundle: .module, comment: "App tours: what Laundry's tour covers"
                ),
                stepCount: 3, systemImage: "basket", isCommon: false),
            TourCatalogEntry(
                id: .laundryOff,
                title: String(localized: "Laundry is off", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Turning tracking on, or not", bundle: .module,
                    comment: "App tours: what the Laundry is off tour covers"),
                stepCount: 2, systemImage: "basket", isCommon: false),
            TourCatalogEntry(
                id: .suitcase,
                title: String(localized: "Inside your suitcase", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Naming, packing and styling from it", bundle: .module,
                    comment: "App tours: what a suitcase's tour covers"),
                stepCount: 3, systemImage: "suitcase", isCommon: false),
            TourCatalogEntry(
                id: .allSuitcases,
                title: String(localized: "All suitcases", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Finding one, archived ones and your whole closet", bundle: .module,
                    comment: "App tours: what All suitcases' tour covers"),
                stepCount: 3, systemImage: "suitcase.rolling", isCommon: false),
            TourCatalogEntry(
                id: .profile, title: String(localized: "Profile", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Your sign, your fit and these tours", bundle: .module,
                    comment: "App tours: what Profile's tour covers"),
                stepCount: 3, systemImage: "person.crop.circle", isCommon: false),
            TourCatalogEntry(
                id: .accessibility,
                title: String(localized: "Accessibility", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Your iPhone’s settings, and where to change them", bundle: .module,
                    comment: "App tours: what Accessibility's tour covers"),
                stepCount: 2, systemImage: "accessibility", isCommon: false),
            TourCatalogEntry(
                id: .help, title: String(localized: "Help", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Answers, and where to ask", bundle: .module,
                    comment: "App tours: what Help's tour covers"
                ),
                stepCount: 2, systemImage: "questionmark.circle", isCommon: false),
            TourCatalogEntry(
                id: .feedback,
                title: String(localized: "Send feedback", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "Writing and sending a note", bundle: .module,
                    comment: "App tours: what Send feedback's tour covers"),
                stepCount: 2, systemImage: "bubble.left", isCommon: false),
            TourCatalogEntry(
                id: .privacy,
                title: String(localized: "Privacy and terms", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "What’s shared, and deleting your data", bundle: .module,
                    comment: "App tours: what Privacy and terms' tour covers"),
                stepCount: 2, systemImage: "hand.raised", isCommon: false),
            TourCatalogEntry(
                id: .deleteData,
                title: String(localized: "Delete my data", bundle: .module, comment: "App tours: a screen"),
                summary: String(
                    localized: "What goes, and how it asks first", bundle: .module,
                    comment: "App tours: what Delete my data's tour covers"),
                stepCount: 2, systemImage: "trash", isCommon: false),
        ]
    }

    /// The entries App tours shows: Laundry's tour for the way laundry tracking is set.
    static func entries(tracksLaundry: Bool) -> [TourCatalogEntry] {
        entries.filter { $0.id != (tracksLaundry ? .laundryOff : .laundry) }
    }

    /// "3 quick tips".
    static func quickTips(_ count: Int) -> String {
        String(
            localized: "\(count) quick tips", bundle: .module,
            comment: "App tours: how many tips a screen's tour has (plural)")
    }
}
