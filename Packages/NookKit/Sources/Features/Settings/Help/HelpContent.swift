import Foundation

/// One short answer on Help (`help.html`, PRD §22.3 "concise help library"): a topic she can open,
/// one or two lines of how-to, and a quieter line of good-to-know.
///
/// The words are bundled in the String Catalog, so help works offline and opening it never
/// changes what she's doing. They describe this build as it is: where the test build differs
/// from the finished app (sample photos, nothing sent), they say so.
nonisolated struct HelpTopic: Identifiable, Hashable, Sendable {
    enum Section: CaseIterable, Sendable {
        case everyday
        case goodToKnow
    }

    let id: String
    let section: Section
    let title: String
    let systemImage: String
    let answer: String
    var note: String?
}

/// Help's topics, in order (`help.html`). "Free and paid" came with the subscription (30a).
nonisolated enum HelpContent {
    /// The topics for the debug sample closet, which comes back as it ships at each launch.
    static var topics: [HelpTopic] { topics(keepsChanges: false) }

    /// The topics, with "Your data" saying whether her changes are kept when the app closes
    /// (`NookServices.keepsChanges`, Phase 21a), and "Free and paid" whether she has styling
    /// access (30a).
    static func topics(keepsChanges: Bool, hasStylingAccess: Bool = false) -> [HelpTopic] {
        [
            HelpTopic(
                id: "outfits", section: .everyday,
                title: String(localized: "Get outfit ideas", bundle: .module, comment: "Help topic"),
                systemImage: "sparkles",
                answer: String(
                    localized:
                        "Tap the laptop on your desk. Check the occasion, then tap Style me. You’ll see one outfit in three versions: Simple, Dressed up and Something new.",
                    bundle: .module, comment: "Help: Get outfit ideas"),
                note: String(
                    localized:
                        "Simple and Dressed up use only your pieces. Something new can add one idea if Preferences allows it. If there aren’t enough pieces, Style Me says what’s missing.",
                    bundle: .module, comment: "Help: Get outfit ideas, the quieter line")),
            HelpTopic(
                id: "swap", section: .everyday,
                title: String(localized: "Swap, save and try on a look", bundle: .module, comment: "Help topic"),
                systemImage: "arrow.left.arrow.right",
                answer: String(
                    localized:
                        "Swap changes one piece and keeps the rest. Save look keeps it in Saved Looks, where you can wear it again.",
                    bundle: .module, comment: "Help: Swap, save and try on"),
                note: String(
                    localized:
                        "Try it on makes a simulated picture of the look, only when you ask: the person in your try-on photo wearing it, or your pieces on their own. Nothing leaves your iPhone.",
                    bundle: .module, comment: "Help: Swap, save and try on, the quieter line")),
            HelpTopic(
                id: "addPiece", section: .everyday,
                title: String(localized: "Add a piece", bundle: .module, comment: "Help topic"),
                systemImage: "plus",
                answer: String(
                    localized:
                        "In Closet, tap Add a piece. Choose a photo, or describe the piece in words. Only a name and a kind are needed.",
                    bundle: .module, comment: "Help: Add a piece"),
                note: keepsChanges
                    ? String(
                        localized:
                            "Details you don’t know can stay empty. The app only sees the photos you pick or take, and keeps its own copy without the location.",
                        bundle: .module, comment: "Help: Add a piece, the quieter line, with real photos (Phase 22a)")
                    : String(
                        localized:
                            "Details you don’t know can stay empty. This test build uses sample photos instead of your camera.",
                        bundle: .module, comment: "Help: Add a piece, the quieter line")),
            HelpTopic(
                id: "suitcases", section: .everyday,
                title: String(localized: "Suitcases", bundle: .module, comment: "Help topic"),
                systemImage: "suitcase",
                answer: String(
                    localized:
                        "A suitcase is a smaller set of your pieces, for a trip or a second home. Tap the suitcase in your room to choose one.",
                    bundle: .module, comment: "Help: Suitcases"),
                note: String(
                    localized:
                        "Styling from a suitcase uses only its pieces. Deleting a suitcase keeps every piece.",
                    bundle: .module, comment: "Help: Suitcases, the quieter line")),
            HelpTopic(
                id: "laundry", section: .everyday,
                title: String(localized: "Laundry", bundle: .module, comment: "Help topic"),
                systemImage: "washer",
                answer: String(
                    localized:
                        "Laundry tracking is a switch in Profile. When it’s on, the hamper shows what’s in the wash and Style Me skips those pieces until you mark them clean.",
                    bundle: .module, comment: "Help: Laundry"),
                note: String(
                    localized: "Turning it off keeps your marks, and every piece counts as available.",
                    bundle: .module, comment: "Help: Laundry, the quieter line")),
            HelpTopic(
                id: "connection", section: .goodToKnow,
                title: String(localized: "What needs a connection", bundle: .module, comment: "Help topic"),
                systemImage: "wifi.slash",
                answer: String(
                    localized:
                        "In this test build nothing needs a connection, and nothing you add is sent anywhere.",
                    bundle: .module, comment: "Help: What needs a connection"),
                note: String(
                    localized:
                        "Later, Style Me, swaps and Try it on will need a connection. Your closet, laundry, suitcases and saved looks will keep working offline.",
                    bundle: .module, comment: "Help: What needs a connection, the quieter line")),
            HelpTopic(
                id: "freeAndPaid", section: .goodToKnow,
                title: String(localized: "Free and paid", bundle: .module, comment: "Help topic"),
                systemImage: "creditcard",
                answer: String(
                    localized:
                        "Your closet, laundry, suitcases, saved looks, search and the looks you make yourself are always free. Style Me, swaps, Ask stylist and try-on pictures use styling access.",
                    bundle: .module, comment: "Help: Free and paid"),
                note: hasStylingAccess
                    ? String(
                        localized:
                            "You have styling access. To cancel or change how you pay, open Profile, then Styling access, then Manage subscription.",
                        bundle: .module, comment: "Help: Free and paid, the quieter line, with styling access")
                    : String(
                        localized:
                            "Styling access is a monthly subscription, and new subscribers get the first month free. Profile, then Styling access, shows the price and Restore purchases.",
                        bundle: .module, comment: "Help: Free and paid, the quieter line, without styling access")),
            HelpTopic(
                id: "fit", section: .goodToKnow,
                title: String(localized: "Try-on pictures and real fit", bundle: .module, comment: "Help topic"),
                systemImage: "camera",
                answer: String(
                    localized:
                        "Try-on pictures are previews. They can’t show how something actually fits. Your measurements and the pieces that fit you well are the better guide.",
                    bundle: .module, comment: "Help: Try-on pictures and real fit")),
            HelpTopic(
                id: "data", section: .goodToKnow,
                title: String(localized: "Your data", bundle: .module, comment: "Help topic"),
                systemImage: "lock",
                answer: keepsChanges
                    ? String(
                        localized:
                            "Everything you add stays on this iPhone, and is kept when the app closes. Delete my data in Profile removes all of it.",
                        bundle: .module, comment: "Help: Your data, when her data is kept")
                    : String(
                        localized:
                            "Everything you add stays on this iPhone. When this test build closes, it keeps your name and your Style Me settings, and forgets your fit and the pieces and looks you add. Privacy and terms says what’s kept, and Delete my data removes all of it.",
                        bundle: .module, comment: "Help: Your data")),
        ]
    }

    static func title(_ section: HelpTopic.Section) -> String {
        switch section {
        case .everyday: String(localized: "Everyday", bundle: .module, comment: "Help section header")
        case .goodToKnow: String(localized: "Good to know", bundle: .module, comment: "Help section header")
        }
    }
}
