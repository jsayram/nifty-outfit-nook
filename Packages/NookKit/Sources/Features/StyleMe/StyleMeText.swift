import Foundation
import Models

/// The words on Style Me (RD-02, LR-03, LR-18): each row's value and line, and what the screen
/// says about anything that stops or limits the request. Kept apart from the views so tests can
/// read them for any draft.
struct StyleMeText {
    let draft: StyleRequestDraft
    let check: StyleRequestCheck
    let startingPiece: Garment?
    /// The suitcase's name when the source is a suitcase that exists.
    let suitcaseName: String?
    let usualFit: Comfort?
    var locale: Locale = .current

    // MARK: Source

    /// "Main closet", the suitcase's name, or a plain stand-in when it's gone.
    var sourceName: String {
        guard draft.source.isSuitcase else { return Self.mainCloset }
        return suitcaseName
            ?? String(localized: "A missing suitcase", bundle: .module, comment: "Style Me source when it's gone")
    }

    /// "17 pieces", or "5 pieces · Suitcase only" for a suitcase (PRD §8.1: Use only this suitcase).
    var sourceDetail: String {
        let count =
            check.piecesInSource == 0
            ? String(localized: "Empty", bundle: .module, comment: "Source plate: the source has no pieces")
            : Self.pieces(check.piecesInSource)
        guard draft.source.isSuitcase else { return count }
        return "\(count) · \(Self.suitcaseOnly)"
    }

    /// What VoiceOver reads for the Source row.
    var sourceLabel: String {
        String(
            localized: "Source: \(sourceName), \(sourceDetail)", bundle: .module,
            comment: "VoiceOver label for Style Me's Source row: the source's name and its pieces")
    }

    static var mainCloset: String {
        String(localized: "Main closet", bundle: .module, comment: "Source plate: the whole closet")
    }

    static var suitcaseOnly: String {
        String(localized: "Suitcase only", bundle: .module, comment: "Source plate: styling uses this suitcase only")
    }

    static func pieces(_ count: Int) -> String {
        String(localized: "\(count) pieces", bundle: .module, comment: "Source plate: how many pieces the source has")
    }

    // MARK: Occasion

    /// "Office", or "Other: museum visit" with her words.
    var occasionValue: String {
        let note = draft.occasionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.occasion == .other, !note.isEmpty else { return draft.occasion.title }
        return String(
            localized: "Other: \(note)", bundle: .module, comment: "Style Me occasion: Other, with her own words")
    }

    // MARK: Starting piece

    var startingPieceValue: String {
        guard draft.startingPieceID != nil else {
            return String(localized: "None", bundle: .module, comment: "Style Me: no starting piece")
        }
        return startingPiece?.name
            ?? String(localized: "A missing piece", bundle: .module, comment: "Style Me: the starting piece is gone")
    }

    /// The line under the Starting piece row.
    var startingPieceDetail: String {
        guard draft.startingPieceID != nil else {
            return String(
                localized: "Optional · from \(sourceName)", bundle: .module,
                comment: "Style Me: no starting piece yet; the source's name")
        }
        if let problem = startingPieceProblem { return problem }
        return String(
            localized: "Your looks are built around it", bundle: .module, comment: "Style Me: starting piece line")
    }

    /// Why the starting piece can't be used, in words, or `nil` when it can.
    var startingPieceProblem: String? {
        for issue in check.issues {
            switch issue {
            case .startingPieceMissing:
                return String(
                    localized: "It isn’t in your closet any more", bundle: .module,
                    comment: "Style Me: the starting piece was removed")
            case .startingPieceUnusable(let reasons):
                return Self.reason(reasons.first ?? .notOwned, sourceName: sourceName)
            default:
                continue
            }
        }
        return nil
    }

    static func reason(_ reason: IneligibilityReason, sourceName: String) -> String {
        switch reason {
        case .outsideSource:
            String(
                localized: "Not packed in \(sourceName)", bundle: .module,
                comment: "Style Me: the starting piece isn't in the suitcase being styled from")
        case .dirty:
            String(localized: "In the wash", bundle: .module, comment: "Style Me: the starting piece is dirty")
        case .unavailable:
            String(localized: "Away right now", bundle: .module, comment: "Style Me: the starting piece is away")
        case .notArrived:
            String(localized: "Hasn’t arrived yet", bundle: .module, comment: "Style Me: bought, not arrived")
        case .notOwned, .noLongerOwned, .deleted, .archived:
            String(
                localized: "It isn’t in your closet any more", bundle: .module,
                comment: "Style Me: the starting piece was removed")
        }
    }

    // MARK: Comfort (LR-18)

    var comfortValue: String {
        draft.comfort?.title
            ?? String(localized: "Usual fit", bundle: .module, comment: "Style Me Comfort: her usual fit from Profile")
    }

    /// "Just for this outfit.", or "Today: fitted (you usually like relaxed)" when today's comfort
    /// differs from her usual fit (LR-18).
    var comfortLine: String {
        if let comfort = draft.comfort, let usualFit, comfort != usualFit {
            let today = comfort.title.lowercased(with: locale)
            let usual = usualFit.title.lowercased(with: locale)
            return String(
                localized: "Today: \(today) (you usually like \(usual))", bundle: .module,
                comment: "Style Me Comfort line when today's comfort differs from her usual fit (LR-18)")
        }
        return Self.justForThisOutfit
    }

    static var justForThisOutfit: String {
        String(localized: "Just for this outfit.", bundle: .module, comment: "Style Me Comfort line (LR-18)")
    }

    // MARK: Colour

    var colorValue: String { Self.colorValue(draft.color, locale: locale) }

    /// "Any", "Navy", "Navy · shoes" or "Navy · shoes · required".
    static func colorValue(_ color: ColorWish?, locale: Locale) -> String {
        guard let color else {
            return String(localized: "Any", bundle: .module, comment: "Style Me Colour: no colour wish")
        }
        var parts = [color.family.title]
        if color.scope != .anyPiece { parts.append(color.scope.title.lowercased(with: locale)) }
        if color.strength == .required {
            parts.append(String(localized: "required", bundle: .module, comment: "Style Me Colour value: a must"))
        }
        return parts.joined(separator: " · ")
    }

    /// What the colour wish means, in a sentence, under the choices in the sheet.
    var colorExplanation: String {
        guard let color = draft.color else {
            return String(
                localized: "Pick a colour to set how strongly it’s used and where.", bundle: .module,
                comment: "Colour sheet note before a colour is picked")
        }
        let name = color.family.title.lowercased(with: locale)
        let place = color.scope.place
        switch color.strength {
        case .preferred:
            return String(
                localized: "Preferred: \(name) \(place) is used when it works. Looks without it can still appear.",
                bundle: .module, comment: "Colour sheet note. Example: navy in the shoes")
        case .required:
            return String(
                localized:
                    "Required: every look has \(name) \(place), using your own pieces. If nothing fits, you’ll see why.",
                bundle: .module, comment: "Colour sheet note. Example: navy in the shoes")
        }
    }

    // MARK: Preferences (LR-03)

    var preferencesValue: String { draft.pieceMode.title }

    var preferencesLine: String {
        if draft.source.isSuitcase {
            return String(
                localized: "From a suitcase, every piece is one you packed.", bundle: .module,
                comment: "Style Me Preferences line when the source is a suitcase (LR-05b)")
        }
        return draft.pieceMode.shortDetail
    }

    // MARK: Notices

    /// What the screen says about one issue, with the ways forward.
    func notice(for issue: StyleRequestIssue) -> StyleMeNotice {
        switch issue {
        case .closetEmpty:
            return StyleMeNotice(
                id: "closetEmpty",
                title: String(
                    localized: "Your closet is empty", bundle: .module, comment: "Style Me when the closet is empty"),
                message: String(
                    localized: "Style Me puts looks together from your own clothes. Add a few pieces first.",
                    bundle: .module, comment: "Style Me when the closet is empty"),
                actions: [.addPiece])
        case .suitcaseMissing:
            return StyleMeNotice(
                id: "suitcaseMissing",
                title: String(
                    localized: "This suitcase isn’t there any more", bundle: .module,
                    comment: "Style Me when the suitcase source was removed or archived"),
                message: String(
                    localized: "Choose where your looks come from.", bundle: .module,
                    comment: "Style Me when the suitcase source was removed or archived"),
                actions: [.chooseSource])
        case .suitcaseEmpty:
            return StyleMeNotice(
                id: "suitcaseEmpty",
                title: String(
                    localized: "\(sourceName) is empty", bundle: .module,
                    comment: "Style Me when the suitcase has nothing packed; the suitcase's name"),
                message: String(
                    localized:
                        "Looks from a suitcase only use what’s packed in it. Pack a few pieces, or style from somewhere else.",
                    bundle: .module, comment: "Style Me when the suitcase has nothing packed"),
                actions: [.addPieces, .chooseSource])
        case .tooFewToStyle(let usable, let total):
            let message =
                usable == 0
                ? String(
                    localized: "Nothing in \(sourceName) can be used today. Pieces in the wash or away don’t count.",
                    bundle: .module, comment: "Style Me: no usable pieces in the source; the source's name")
                : String(
                    localized:
                        "Only \(usable) of \(total) pieces in \(sourceName) can be used today. A look needs at least \(StyleRequestBuilder.minimumPieces).",
                    bundle: .module, comment: "Style Me: too few usable pieces; counts and the source's name")
            return StyleMeNotice(
                id: "tooFewToStyle",
                title: String(
                    localized: "Not enough to style yet", bundle: .module,
                    comment: "Style Me when too few pieces can be used"),
                message: message,
                actions: draft.source.isSuitcase ? [.addPieces, .chooseSource] : [.addPiece])
        case .fewPieces(let usable):
            return StyleMeNotice(
                id: "fewPieces",
                title: nil,
                message: String(
                    localized:
                        "\(sourceName) has \(usable) pieces you can use today, so you may get fewer than three versions.",
                    bundle: .module, comment: "Style Me warning: a small suitcase; its name and a count"),
                actions: [])
        case .startingPieceMissing, .startingPieceUnusable:
            let reason = startingPieceProblem ?? ""
            return StyleMeNotice(
                id: "startingPiece",
                title: nil,
                message: String(
                    localized: "\(startingPieceValue) can’t be your starting piece. \(reason).",
                    bundle: .module,
                    comment: "Style Me: the starting piece can't be used; its name, then why, such as In the wash"),
                actions: [.chooseStartingPiece, .clearStartingPiece])
        case .occasionNoteInvalid(let problem):
            return StyleMeNotice(
                id: "occasionNote",
                title: nil,
                message: Self.occasionNoteProblem(problem),
                actions: [.chooseOccasion])
        case .requiredColorUnavailable(let color):
            let name = color.family.title.lowercased(with: locale)
            return StyleMeNotice(
                id: "requiredColor",
                title: nil,
                message: String(
                    localized: "No \(name) \(color.scope.kinds) in \(sourceName) can be used today.",
                    bundle: .module, comment: "Style Me warning. Example: No navy shoes in Weekend can be used today."),
                actions: [.makeColorPreferred])
        }
    }

    static func occasionNoteProblem(_ problem: NameProblem) -> String {
        switch problem {
        case .tooLong(let maximum):
            String(
                localized: "Keep it to \(maximum) characters.", bundle: .module,
                comment: "Problem with the words for Other")
        case .controlCharacters, .empty, .duplicate:
            String(
                localized: "Use one line, without line breaks.", bundle: .module,
                comment: "Problem with the words for Other")
        }
    }

    /// The notices to show, blocking ones first.
    var notices: [StyleMeNotice] {
        (check.blockingIssues + check.warnings).map(notice(for:))
    }

    /// The line under the Style me button.
    var buttonCaption: String {
        if check.canStyle {
            return String(
                localized: "Uses 1 styling request.", bundle: .module, comment: "Under the Style me button")
        }
        return String(
            localized: "Style me works once the note above is sorted.", bundle: .module,
            comment: "Under the Style me button while something stops it")
    }
}

/// A note on Style Me about something that stops or limits the request, with its ways forward.
nonisolated struct StyleMeNotice: Hashable, Identifiable, Sendable {
    let id: String
    let title: String?
    let message: String
    let actions: [StyleMeNoticeAction]
}

/// A way forward from a notice.
nonisolated enum StyleMeNoticeAction: String, Hashable, Sendable {
    case addPiece
    case addPieces
    case chooseSource
    case chooseStartingPiece
    case clearStartingPiece
    case chooseOccasion
    case makeColorPreferred

    var title: String {
        switch self {
        case .addPiece: String(localized: "Add a piece", bundle: .module, comment: "Button: adds a piece to the closet")
        case .addPieces:
            String(localized: "Add pieces", bundle: .module, comment: "Style Me button: opens Suitcases to pack")
        case .chooseSource:
            String(localized: "Choose another source", bundle: .module, comment: "Style Me button")
        case .chooseStartingPiece:
            String(localized: "Choose another", bundle: .module, comment: "Style Me button: another starting piece")
        case .clearStartingPiece:
            String(localized: "No starting piece", bundle: .module, comment: "Style Me button and sheet choice")
        case .chooseOccasion:
            String(localized: "Change the occasion", bundle: .module, comment: "Style Me button")
        case .makeColorPreferred:
            String(localized: "Make it preferred", bundle: .module, comment: "Style Me button: colour wish")
        }
    }

    var systemImage: String {
        switch self {
        case .addPiece, .addPieces: "plus"
        case .chooseSource: "suitcase"
        case .chooseStartingPiece: "hanger"
        case .clearStartingPiece: "xmark"
        case .chooseOccasion: "calendar"
        case .makeColorPreferred: "paintpalette"
        }
    }
}

// MARK: - Words for the request's values

extension Comfort {
    /// Today's comfort, as on the Comfort sheet: "Fitted", "Comfortable", "Relaxed".
    var title: String {
        switch self {
        case .fitted: String(localized: "Fitted", bundle: .module, comment: "Comfort choice")
        case .comfortable: String(localized: "Comfortable", bundle: .module, comment: "Comfort choice")
        case .relaxed: String(localized: "Relaxed", bundle: .module, comment: "Comfort choice")
        }
    }
}

extension PieceMode {
    /// Preferences' two values (LR-03).
    var title: String {
        switch self {
        case .mineAndOneIdea: String(localized: "Mine + one idea", bundle: .module, comment: "Preferences value")
        case .onlyMine: String(localized: "Only mine", bundle: .module, comment: "Preferences value")
        }
    }

    /// What it means, in the Preferences sheet (LR-03, LR-05b).
    var detail: String {
        switch self {
        case .mineAndOneIdea:
            String(
                localized:
                    "Your own clothes first. Something new adds one piece you don’t have, marked “Not in your closet”.",
                bundle: .module, comment: "Preferences sheet: Mine + one idea")
        case .onlyMine:
            String(
                localized: "Every piece in every version is one you own.", bundle: .module,
                comment: "Preferences sheet: Only mine")
        }
    }

    /// The short line under the Preferences row.
    var shortDetail: String {
        switch self {
        case .mineAndOneIdea:
            String(
                localized: "Something new may add one idea", bundle: .module,
                comment: "Style Me Preferences line for Mine + one idea")
        case .onlyMine:
            String(
                localized: "Only pieces you own", bundle: .module, comment: "Style Me Preferences line for Only mine")
        }
    }
}

extension ColorStrength {
    var title: String {
        switch self {
        case .preferred: String(localized: "Preferred", bundle: .module, comment: "Colour sheet: how strongly")
        case .required: String(localized: "Required", bundle: .module, comment: "Colour sheet: how strongly")
        }
    }
}

extension ColorScope {
    /// The Applies to chips.
    var title: String {
        switch self {
        case .anyPiece: String(localized: "Any one piece", bundle: .module, comment: "Colour sheet: applies to")
        case .top: String(localized: "Top", bundle: .module, comment: "Colour sheet: applies to")
        case .bottom: String(localized: "Bottom", bundle: .module, comment: "Colour sheet: applies to")
        case .dress: String(localized: "Dress", bundle: .module, comment: "Colour sheet: applies to")
        case .layer: String(localized: "Layer", bundle: .module, comment: "Colour sheet: applies to")
        case .shoes: String(localized: "Shoes", bundle: .module, comment: "Colour sheet: applies to")
        case .wholePalette: String(localized: "Overall palette", bundle: .module, comment: "Colour sheet: applies to")
        }
    }

    /// Where the colour goes, after its name: "navy in the shoes".
    var place: String {
        switch self {
        case .anyPiece:
            String(localized: "in one piece", bundle: .module, comment: "Colour place, as in navy in one piece")
        case .top: String(localized: "in the top", bundle: .module, comment: "Colour place, as in navy in the top")
        case .bottom:
            String(localized: "in the bottom", bundle: .module, comment: "Colour place, as in navy in the bottom")
        case .dress:
            String(localized: "in the dress", bundle: .module, comment: "Colour place, as in navy in the dress")
        case .layer:
            String(localized: "in the layer", bundle: .module, comment: "Colour place, as in navy in the layer")
        case .shoes:
            String(localized: "in the shoes", bundle: .module, comment: "Colour place, as in navy in the shoes")
        case .wholePalette:
            String(localized: "across the look", bundle: .module, comment: "Colour place, as in navy across the look")
        }
    }

    /// The pieces that could carry it, after a colour: "navy shoes", "navy pieces".
    var kinds: String {
        switch self {
        case .anyPiece, .wholePalette:
            String(localized: "pieces", bundle: .module, comment: "As in: No navy pieces in Weekend")
        case .top: String(localized: "tops", bundle: .module, comment: "As in: No navy tops in Weekend")
        case .bottom: String(localized: "bottoms", bundle: .module, comment: "As in: No navy bottoms in Weekend")
        case .dress: String(localized: "dresses", bundle: .module, comment: "As in: No navy dresses in Weekend")
        case .layer: String(localized: "layers", bundle: .module, comment: "As in: No navy layers in Weekend")
        case .shoes: String(localized: "shoes", bundle: .module, comment: "As in: No navy shoes in Weekend")
        }
    }
}
