import Foundation
import Models

/// The words on Make your own look (LR-08).
enum LookBuilderText {
    static var title: String {
        String(localized: "Make your own look", bundle: .module, comment: "Screen title")
    }

    /// The tour's first line, also the screen's lead (LR-08).
    static var lead: String {
        String(
            localized: "Build an outfit yourself, piece by piece.", bundle: .module,
            comment: "Make your own look: the line at the top (LR-08)")
    }

    static var source: String {
        String(
            localized:
                "Pieces from Main closet that you can wear today. Nothing is sent, and no styling request is used.",
            bundle: .module, comment: "Make your own look: where the pieces come from (FR-32)")
    }

    static var namePrompt: String {
        String(localized: "Name this look", bundle: .module, comment: "Make your own look: name field prompt")
    }

    static var nameLabel: String {
        String(localized: "Name", bundle: .module, comment: "Make your own look: name field label")
    }

    static var emptyLook: String {
        String(
            localized: "Your look shows here as you add pieces.", bundle: .module,
            comment: "Make your own look: before any piece is added")
    }

    static var addPiece: String {
        String(localized: "Add a piece", bundle: .module, comment: "Make your own look: opens the piece picker")
    }

    static var pickerTitle: String {
        String(localized: "Add a piece", bundle: .module, comment: "Make your own look: opens the piece picker")
    }

    static var pickerLead: String {
        String(
            localized: "One of each kind. A piece of a kind the look already has takes its place.", bundle: .module,
            comment: "Make your own look: under the picker's title")
    }

    static var pickerHint: String {
        String(localized: "Adds it to the look.", bundle: .module, comment: "Make your own look: hint on a piece")
    }

    static var change: String {
        String(localized: "Change", bundle: .module, comment: "Make your own look: changes a piece")
    }

    static func changeLabel(kind: GarmentCategory, name: String) -> String {
        let kindTitle = kind.singularTitle
        return String(
            localized: "Change the \(kindTitle), now \(name)", bundle: .module,
            comment: "Spoken label of Change: the kind of piece and the piece")
    }

    static func removeLabel(_ name: String) -> String {
        String(localized: "Remove \(name)", bundle: .module, comment: "Spoken label of a piece's remove button")
    }

    static var save: String {
        String(localized: "Save look", bundle: .module, comment: "Results button (RD-06)")
    }

    static var saveChanges: String {
        String(
            localized: "Save changes", bundle: .module, comment: "Make your own look: Save after editing a saved look")
    }

    static var saved: String {
        String(localized: "Saved", bundle: .module, comment: "Save look button once the look is saved")
    }

    static var savedLine: String {
        String(
            localized: "In Saved Looks. Saved looks work without pictures or credits.", bundle: .module,
            comment: "Make your own look: under Save once saved")
    }

    static var readyLine: String {
        String(
            localized: "Saved looks work without pictures or credits. An empty name is filled in from the colours.",
            bundle: .module, comment: "Make your own look: under Save while it can be saved")
    }

    static var savedLooksFree: String {
        String(
            localized: "Saved looks work without pictures or credits.", bundle: .module,
            comment: "Make your own look: under Save once she typed a name")
    }

    static var fallbackName: String {
        String(localized: "My look", bundle: .module, comment: "Name of a look she made with no main colours")
    }

    static var saveFailed: String {
        String(
            localized: "That look couldn’t be saved. Try again.", bundle: .module,
            comment: "Toast when saving a look fails")
    }

    static var draftNotKept: String {
        String(
            localized: "This look can’t be kept as a draft right now. Save it to keep it.", bundle: .module,
            comment: "Make your own look: the draft couldn't be written")
    }

    /// What stops Save, in words.
    static func line(for problem: LookProblem, garments: [Garment.ID: Garment]) -> String {
        switch problem {
        case .tooFewPieces:
            String(
                localized: "A look needs at least 2 pieces.", bundle: .module,
                comment: "Make your own look: why Save is off")
        case .tooManyPieces:
            String(
                localized: "A look has at most 6 pieces. Remove one to save.", bundle: .module,
                comment: "Make your own look: why Save is off")
        case .needsMainPieces:
            String(
                localized: "A look needs a top and a bottom, or a dress.", bundle: .module,
                comment: "Make your own look: why Save is off")
        case .twoOfAKind:
            String(
                localized: "A look holds one piece of each kind.", bundle: .module,
                comment: "Make your own look: why Save is off")
        case .notUsable(let id, _):
            notUsable(garments[id]?.name ?? "")
        }
    }

    private static func notUsable(_ name: String) -> String {
        String(
            localized: "\(name) can’t be worn today. Take it out or change it.", bundle: .module,
            comment: "Make your own look: why Save is off, with the piece")
    }

    static func nameLine(for problem: NameProblem) -> String {
        switch problem {
        case .tooLong(let maximum):
            String(
                localized: "Use \(maximum) characters or fewer.", bundle: .module,
                comment: "Make your own look: the name is too long")
        case .empty, .controlCharacters, .duplicate:
            String(
                localized: "Use one line of letters, numbers and spaces.", bundle: .module,
                comment: "Make your own look: the name has line breaks or tabs")
        }
    }

    // MARK: Draft card

    static var draftTitle: String {
        String(localized: "Continue your look?", bundle: .module, comment: "Make your own look: draft card title")
    }

    static func draftMessage(_ draft: LookDraft) -> String {
        let pieces = StyleMeText.pieces(draft.garmentIDs.count)
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return String(
                localized: "You started a look with \(pieces) and didn’t save it.", bundle: .module,
                comment: "Make your own look: draft card, with how many pieces, as in 3 pieces")
        }
        return String(
            localized: "You started “\(name)” with \(pieces) and didn’t save it.", bundle: .module,
            comment: "Make your own look: draft card, with the look's name and how many pieces")
    }

    static var resume: String {
        String(localized: "Resume", bundle: .module, comment: "Button: carries on with a draft")
    }

    static var startOver: String {
        String(localized: "Start over", bundle: .module, comment: "Make your own look: throws the draft away")
    }

    // MARK: Toasts

    static func added(_ name: String) -> String {
        String(localized: "Added \(name)", bundle: .module, comment: "Make your own look: status after adding")
    }

    static var savedToast: String {
        String(localized: "Saved to Saved Looks", bundle: .module, comment: "Toast after Save look")
    }
}
