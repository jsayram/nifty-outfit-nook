import Foundation
import Models

/// The words on Saved Looks and look detail.
enum SavedLooksText {
    static var title: String { AppTab.savedLooks.title }

    /// "5 looks", "1 look".
    static func looks(_ count: Int) -> String {
        String(
            localized: "\(count) looks", bundle: .module, comment: "Saved Looks: how many looks she saved")
    }

    /// "2 of 5 looks" while filtering.
    static func shown(_ count: Int, of total: String) -> String {
        String(
            localized: "\(count) of \(total)", bundle: .module,
            comment: "Saved Looks count while filtering: how many match, of how many looks, as in 2 of 5 looks")
    }

    /// The name of a saved look that has none: "Office look", or "Saved look".
    static func unnamed(occasion: String?) -> String {
        guard let occasion else {
            return String(localized: "Saved look", bundle: .module, comment: "Name of a saved look with no name")
        }
        return String(
            localized: "\(occasion) look", bundle: .module,
            comment: "Name of a saved look with no main colours: the occasion")
    }

    static var looksTab: String {
        String(localized: "Looks", bundle: .module, comment: "Saved Looks tab: her saved looks (RD-08)")
    }

    static var picturesTab: String {
        String(localized: "Pictures", bundle: .module, comment: "Saved Looks tab: her try-on pictures (RD-08)")
    }

    static var tabsTitle: String {
        String(localized: "Show", bundle: .module, comment: "Spoken name of the Looks and Pictures switch")
    }

    static var searchPrompt: String {
        String(localized: "Search your looks", bundle: .module, comment: "Saved Looks search field prompt (RD-08)")
    }

    static var makeYourOwn: String {
        String(
            localized: "+ Make your own", bundle: .module,
            comment: "Saved Looks: opens Make your own look (RD-08, LR-08)")
    }

    static var makeYourOwnSpoken: String {
        String(localized: "Make your own look", bundle: .module, comment: "Spoken label of + Make your own")
    }

    // MARK: States

    static var loading: String {
        String(localized: "Opening your saved looks", bundle: .module, comment: "Saved Looks loading")
    }

    static var failedTitle: String {
        String(localized: "Your saved looks didn’t load", bundle: .module, comment: "Saved Looks error title")
    }

    static var failedMessage: String {
        String(
            localized: "Nothing was lost. Try again in a moment.", bundle: .module, comment: "Closet error message")
    }

    static var emptyTitle: String {
        String(localized: "Nothing saved yet", bundle: .module, comment: "Saved Looks with no looks (RD-08.4)")
    }

    static var emptyMessage: String {
        String(
            localized: "Looks you keep show up here, ready to wear again.", bundle: .module,
            comment: "Saved Looks with no looks (RD-08.4)")
    }

    /// How to save a look, step by step (RD-08.4).
    static var emptySteps: [String] {
        [
            String(
                localized: "Open Style Me from the laptop on Home and ask for a look.", bundle: .module,
                comment: "Saved Looks empty state: step 1"),
            String(
                localized: "On Your looks, tap Save look.", bundle: .module,
                comment: "Saved Looks empty state: step 2"),
            String(
                localized: "Or put one together yourself with Make your own.", bundle: .module,
                comment: "Saved Looks empty state: step 3"),
        ]
    }

    static var noMatchesTitle: String {
        String(localized: "No saved looks match", bundle: .module, comment: "Saved Looks: nothing matches (LR-09.3)")
    }

    static var clearFilters: String {
        String(localized: "Clear filters", bundle: .module, comment: "Button: clears every filter and the search")
    }

    // MARK: Pictures tab (12b)

    static var picturesTitle: String {
        String(localized: "No try-on pictures yet", bundle: .module, comment: "Saved Looks Pictures tab, empty")
    }

    static var picturesMessage: String {
        String(
            localized:
                "Pictures are made one look at a time, only when you ask, and they’re simulated. They’ll show here with the look each one came from.",
            bundle: .module, comment: "Saved Looks Pictures tab, empty")
    }

    // MARK: Grid

    /// What VoiceOver says after a look's name and pieces: "Office, Last worn 5 days ago, 1 piece
    /// no longer in your closet".
    static func spokenDetail(of item: SavedLookItem, lastWorn: String?) -> String {
        var parts = [item.occasion, lastWorn].compactMap(\.self)
        if item.removedCount > 0 {
            parts.append(removedCount(item.removedCount))
        }
        return parts.joined(separator: ", ")
    }

    /// "1 piece is no longer in your closet".
    static func removedCount(_ count: Int) -> String {
        String(
            localized: "\(count) pieces no longer in your closet", bundle: .module,
            comment: "Saved Looks: how many of a look's pieces left her closet (LR-16)")
    }

    static var openHint: String {
        String(localized: "Opens this look.", bundle: .module, comment: "Hint on a saved look")
    }
}
