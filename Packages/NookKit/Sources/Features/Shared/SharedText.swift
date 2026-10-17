import Foundation

/// Words more than one feature shows, kept in one place so they stay the same everywhere.
enum SharedText {
    /// The badge on anything simulated in Stage A: the stylist while it works, and every try-on
    /// picture (RD-06.4).
    static var simulated: String {
        String(localized: "Simulated", bundle: .module, comment: "Badge: a stand-in, not the real thing")
    }

    /// The fine print under the results buttons and on a saved look (RD-06).
    static var tryOnPicturesSimulated: String {
        String(
            localized: "Try-on pictures are simulated.", bundle: .module,
            comment: "Fine print under the results buttons and on a saved look (RD-06)")
    }

    /// The name of Command-F, which goes to search on Closet and Saved Looks, in the keyboard's
    /// shortcut list (iPad, Stage A).
    static var searchShortcut: String {
        String(localized: "Search", bundle: .module, comment: "Keyboard shortcut (Command-F) that goes to search")
    }
}
