import Foundation
import Models

/// The words on look detail.
enum LookDetailText {
    /// "Saved today", "Saved yesterday", "Saved 28 Aug".
    static func saved(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        switch WearRules.days(from: date, to: now, calendar: calendar) {
        case ..<1:
            return String(localized: "Saved today", bundle: .module, comment: "Look detail: when she saved the look")
        case 1:
            return String(
                localized: "Saved yesterday", bundle: .module, comment: "Look detail: when she saved the look")
        default:
            let formatted = ShortDateText.format(date, now: now, calendar: calendar, locale: locale)
            return String(
                localized: "Saved \(formatted)", bundle: .module,
                comment: "Look detail: when she saved the look, a date such as 28 Aug")
        }
    }

    /// "From Weekend", for a look made from a suitcase.
    static func from(_ sourceName: String) -> String {
        String(
            localized: "From \(sourceName)", bundle: .module,
            comment: "Look detail: the suitcase the look was made from")
    }

    // MARK: Buttons

    static var wearToday: String {
        String(localized: "Wear today", bundle: .module, comment: "Look detail button (LR-10)")
    }

    static var wornToday: String {
        String(localized: "Worn today", bundle: .module, comment: "Look detail button after Wear today (LR-10)")
    }

    static var wearTodayHint: String {
        String(
            localized: "Marks this look and its pieces as worn today. Laundry doesn’t change.", bundle: .module,
            comment: "Hint on Wear today")
    }

    static var wornTodayHint: String {
        String(
            localized: "Takes today off this look and its pieces.", bundle: .module,
            comment: "Hint on Worn today")
    }

    static var swap: String {
        String(localized: "Swap a piece", bundle: .module, comment: "Results button (RD-06, LR-08)")
    }

    static var tryOn: String {
        String(localized: "Try it on", bundle: .module, comment: "Results button (RD-06)")
    }

    static var rename: String {
        String(localized: "Rename", bundle: .module, comment: "Look detail button: renames the look")
    }

    static var delete: String {
        String(localized: "Delete look", bundle: .module, comment: "Look detail button: takes it out of Saved Looks")
    }

    static var deleteHint: String {
        String(
            localized: "Takes it out of Saved Looks. You can undo it straight after.", bundle: .module,
            comment: "Hint on Delete look")
    }

    static var simulated: String {
        String(
            localized: "Try-on pictures are simulated.", bundle: .module, comment: "Fine print under results buttons")
    }

    static var piecesHeading: String {
        String(localized: "Pieces", bundle: .module, comment: "Look detail: heading over the piece list")
    }

    // MARK: Pieces that left her closet

    /// The kind note when pieces left her closet (LR-16.4).
    static func removedNote(_ pieces: [LookBundlePiece]) -> String {
        if pieces.count == 1, let piece = pieces.first {
            return String(
                localized:
                    "\(piece.name) isn’t in your closet any more. Swap it for one of your pieces, or keep the look as it is.",
                bundle: .module, comment: "Look detail: one piece left her closet (LR-16.4)")
        }
        return String(
            localized:
                "\(pieces.count) pieces aren’t in your closet any more. Swap them for your own, or keep the look as it is.",
            bundle: .module, comment: "Look detail: several pieces left her closet (LR-16.4)")
    }

    /// A piece deleted for good can't be shown.
    static func gone(_ count: Int) -> String {
        String(
            localized: "\(count) pieces were deleted for good, so they don’t show here.", bundle: .module,
            comment: "Look detail: pieces purged from Recently deleted")
    }

    // MARK: Missing

    static var missingTitle: String {
        String(localized: "This look isn’t saved any more", bundle: .module, comment: "Look detail: the look is gone")
    }

    static var missingMessage: String {
        String(
            localized: "It may have been deleted on another screen.", bundle: .module,
            comment: "Look detail: the look is gone")
    }

    static var failedTitle: String {
        String(localized: "This look didn’t load", bundle: .module, comment: "Look detail error title")
    }

    // MARK: Toasts

    static var wornTodayToast: String {
        String(localized: "Marked as worn today", bundle: .module, comment: "Toast after Wear today")
    }

    static var wearRemovedToast: String {
        String(localized: "Took today off this look", bundle: .module, comment: "Toast after tapping Worn today")
    }

    static func deleted(_ name: String) -> String {
        String(
            localized: "Deleted \(name)", bundle: .module,
            comment: "Toast after Delete look, with the look's name")
    }

    static var renamed: String {
        String(localized: "Name saved", bundle: .module, comment: "Toast after renaming a look")
    }

    static var failedToast: String {
        String(
            localized: "That didn’t save. Try again in a moment.", bundle: .module,
            comment: "Toast when a change to a saved look couldn't be saved")
    }

    // MARK: Rename sheet

    static var renameTitle: String {
        String(localized: "Rename look", bundle: .module, comment: "Sheet title")
    }

    static var nameLabel: String {
        String(localized: "Name", bundle: .module, comment: "Label of a look's name field")
    }

    static var save: String {
        String(localized: "Save", bundle: .module, comment: "Button: saves the new name")
    }

    /// Why a name can't be saved, in words.
    static func nameLine(for problem: NameProblem) -> String {
        switch problem {
        case .empty:
            String(
                localized: "Give the look a name.", bundle: .module, comment: "Rename look: the name is empty")
        case .tooLong(let maximum):
            String(
                localized: "Use \(maximum) characters or fewer.", bundle: .module,
                comment: "Make your own look: the name is too long")
        case .controlCharacters, .duplicate:
            String(
                localized: "Use one line of letters, numbers and spaces.", bundle: .module,
                comment: "Make your own look: the name has line breaks or tabs")
        }
    }
}
