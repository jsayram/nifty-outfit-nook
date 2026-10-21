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

    /// "10 looks, 3 not saved", the count under the title on All.
    static func withUnsaved(_ total: String, unsaved: Int) -> String {
        String(
            localized: "\(total), \(unsaved) not saved", bundle: .module,
            comment: "Saved Looks, All: the count under the title, as in 10 looks, 3 not saved")
    }

    // MARK: Saved and All (Phase 21c)

    static var scopeTitle: String {
        String(
            localized: "Which looks to show", bundle: .module,
            comment: "Spoken name of the Saved and All switch on Saved Looks")
    }

    static var savedScope: String {
        String(localized: "Saved", bundle: .module, comment: "Saved Looks switch: only the looks she saved")
    }

    static var allScope: String {
        String(
            localized: "All", bundle: .module,
            comment: "Saved Looks switch: saved looks and the Style Me results she didn’t save")
    }

    static var savedScopeHint: String {
        String(
            localized: "Only the looks you saved.", bundle: .module, comment: "Hint on the Saved option of the switch")
    }

    static var allScopeHint: String {
        String(
            localized: "Your saved looks and the Style Me results you didn’t save.", bundle: .module,
            comment: "Hint on the All option of the switch")
    }

    /// The line at the end of Saved's results: "3 more in All".
    static func moreInAll(_ count: Int) -> String {
        String(
            localized: "\(count) more in All", bundle: .module,
            comment: "Saved Looks, Saved: how many more looks the search and filters find in All, as in 3 more in All")
    }

    static var moreInAllHint: String {
        String(
            localized: "Shows all your looks, including ones you didn’t save. Your search and filters stay on.",
            bundle: .module, comment: "Hint on the 3 more in All button")
    }

    /// The tag on a look she hasn't saved, in All.
    static var notSaved: String { LookDetailText.notSaved }

    /// What VoiceOver says for Save look on one look in the grid: "Save look: Casual look".
    static func saveLookSpoken(_ name: String) -> String {
        String(
            localized: "Save look: \(name)", bundle: .module,
            comment: "Spoken label of Save look on a look in Saved Looks, All")
    }

    static var saveLookHint: String {
        String(
            localized: "Adds this look to your saved looks.", bundle: .module,
            comment: "Hint on Save look on a look in Saved Looks, All")
    }

    /// Under the empty Saved list when she has results she didn't save.
    static var emptyUnsavedHint: String {
        String(
            localized: "Results you didn’t save are in All.", bundle: .module,
            comment: "Saved Looks, Saved with nothing saved: where her unsaved results are")
    }

    static var emptyAllTitle: String {
        String(localized: "No looks yet", bundle: .module, comment: "Saved Looks, All: nothing at all")
    }

    static var emptyAllMessage: String {
        String(
            localized: "Looks Style Me makes for you show up here, saved or not.", bundle: .module,
            comment: "Saved Looks, All: nothing at all")
    }

    static var noMatchesAllTitle: String {
        String(localized: "No looks match in All", bundle: .module, comment: "Saved Looks, All: nothing matches")
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

    // MARK: Grid

    /// What VoiceOver says after a look's name and pieces: "Office, Last worn 5 days ago, 1 piece
    /// no longer in your closet". A look she hasn't saved says when it was made and "Not saved".
    static func spokenDetail(of item: SavedLookItem, lastWorn: String?, made: String? = nil) -> String {
        var parts = [item.occasion, lastWorn, item.isSaved ? nil : made].compactMap(\.self)
        if item.removedCount > 0 {
            parts.append(removedCount(item.removedCount))
        }
        if !item.isSaved { parts.append(notSaved) }
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

    /// In a wide window, where the look shows beside the grid (Phase 15b).
    static var showBesideHint: String {
        String(
            localized: "Shows this look beside your looks.", bundle: .module,
            comment: "Hint on a saved look on iPad, where its detail opens beside the grid")
    }

    // MARK: Beside the grid (Phase 15b)

    static var pickLookTitle: String {
        String(localized: "Pick a look", bundle: .module, comment: "Beside Saved Looks' grid on iPad")
    }

    static var pickLookMessage: String {
        String(
            localized: "It shows here, next to your looks.", bundle: .module,
            comment: "Beside Saved Looks' grid on iPad, before she picks a look")
    }

    static var pickPictureTitle: String {
        String(localized: "Pick a picture", bundle: .module, comment: "Beside the Pictures tab's grid on iPad")
    }

    static var pickPictureMessage: String {
        String(
            localized: "It shows here, next to your pictures.", bundle: .module,
            comment: "Beside the Pictures tab's grid on iPad, before she picks a picture")
    }
}
