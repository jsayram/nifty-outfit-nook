import Foundation
import Models

/// The words on Your looks (LR-05a, LR-05b, LR-06, RD-06, LR-10). Kept apart from the views so
/// tests can read them for any result.
struct YourLooksText {
    let request: StyleRequest
    /// The suitcase's name when the source is a suitcase.
    let suitcaseName: String?
    var locale: Locale = .current

    // MARK: The request line

    /// "Main closet", or the suitcase's name.
    var sourceName: String {
        guard request.source.isSuitcase else { return StyleMeText.mainCloset }
        return suitcaseName
            ?? String(localized: "A missing suitcase", bundle: .module, comment: "Style Me source when it's gone")
    }

    /// "Office", or "Other: museum visit".
    var occasionValue: String {
        guard request.occasion == .other, let note = request.occasionNote, !note.isEmpty else {
            return request.occasion.title
        }
        return String(
            localized: "Other: \(note)", bundle: .module, comment: "Style Me occasion: Other, with her own words")
    }

    /// The quiet line that repeats the request (LR-05a): "Office · Main closet · 58° and rain".
    /// The weather is left out when she ignored it or it couldn't be read.
    var requestLine: String {
        var parts = [occasionValue, sourceName]
        switch request.weatherChoice {
        case .useToday:
            if let weather = request.weather { parts.append(WeatherWords.summary(weather, locale: locale)) }
        case .indoors:
            parts.append(String(localized: "Indoors", bundle: .module, comment: "Weather row value: she'll be indoors"))
        case .ignore:
            break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Tabs and versions

    static func title(of tab: YourLooksModel.Tab) -> String {
        switch tab {
        case .today: String(localized: "Today", bundle: .module, comment: "Your looks tab: the current result (LR-06)")
        case .saved: String(localized: "Saved", bundle: .module, comment: "Your looks tab: looks she saved (LR-06)")
        }
    }

    static func title(of version: LookVersion) -> String {
        switch version {
        case .simple: String(localized: "Simple", bundle: .module, comment: "Look version (LR-05a)")
        case .dressedUp: String(localized: "Dressed up", bundle: .module, comment: "Look version (LR-05a)")
        case .somethingNew: String(localized: "Something new", bundle: .module, comment: "Look version (LR-05a)")
        }
    }

    /// The line under the version switch. Something new without an idea piece (Only mine, or a
    /// suitcase) says it's another version of her own pieces (LR-05b).
    static func description(of version: LookVersion, hasIdea: Bool) -> String {
        switch version {
        case .simple:
            String(localized: "Easy and safe", bundle: .module, comment: "Under the version switch: Simple")
        case .dressedUp:
            String(
                localized: "The same outfit, a little classier", bundle: .module,
                comment: "Under the version switch: Dressed up")
        case .somethingNew:
            hasIdea
                ? String(
                    localized: "The same outfit, plus one piece you don’t have", bundle: .module,
                    comment: "Under the version switch: Something new with a piece she doesn't own")
                : String(
                    localized: "The same outfit, another way with your own pieces", bundle: .module,
                    comment: "Under the version switch: Something new with Only mine or from a suitcase")
        }
    }

    // MARK: Notes

    /// A quiet note with the result.
    func line(for note: ResultNote, now: Date, calendar: Calendar) -> String {
        switch note {
        case .wornRecently(let lastWorn):
            let days = WearRules.days(from: lastWorn, to: now, calendar: calendar)
            switch days {
            case ...0:
                return String(
                    localized: "You wore this today", bundle: .module, comment: "Recent-wear note on Your looks (LR-10)"
                )
            case 1:
                return String(
                    localized: "You wore this yesterday", bundle: .module,
                    comment: "Recent-wear note on Your looks (LR-10)")
            default:
                return String(
                    localized: "You wore this \(days) days ago", bundle: .module,
                    comment: "Recent-wear note on Your looks (LR-10): how many days ago")
            }
        case .noNewPieceInSuitcase:
            return String(
                localized:
                    "Looks from \(sourceName) use only what’s packed, so Something new is made from your own pieces.",
                bundle: .module, comment: "Note on Your looks from a suitcase (LR-05b): the suitcase's name")
        case .weatherUnavailable:
            return String(
                localized: "The weather couldn’t be read, so these looks don’t use it.", bundle: .module,
                comment: "Note on Your looks (LR-04.3)")
        case .requiredColorNotMet(let family):
            let colour = family.title.lowercased(with: locale)
            return String(
                localized: "Nothing in \(sourceName) could bring in \(colour) here, so this look goes without it.",
                bundle: .module, comment: "Note on Your looks: a required colour couldn't be met; the source and colour"
            )
        case .noOtherOutfit:
            return String(
                localized: "That’s every outfit \(sourceName) can make for this request, so this one came round again.",
                bundle: .module, comment: "Note on Your looks after Try a different outfit: the source's name")
        case .fromHistory:
            return String(
                localized: "From your history: it still fits today’s request, so nothing was used.",
                bundle: .module, comment: "Note on Your looks: an earlier result reused before asking the stylist (FR-58)")
        case .answeredAgain:
            return String(
                localized: "You asked for the same thing earlier today, so these are the same looks. Nothing was used.",
                bundle: .module, comment: "Note on Your looks: the server answered from its 24-hour result cache")
        }
    }

    /// Says kindly which versions are missing and why (PartialWardrobe).
    func partialLine(missing: [MissingVersion]) -> String? {
        guard let first = missing.first else { return nil }
        let names = missing.map { Self.title(of: $0.version) }.formatted(.list(type: .and).locale(locale))
        let reason: String =
            switch first.reason {
            case .noDressierPiece:
                String(
                    localized: "\(sourceName) has no dressier piece to swap in.", bundle: .module,
                    comment: "Why a version is missing: the source's name")
            case .noOtherOwnedPiece:
                String(
                    localized: "\(sourceName) has no other piece to make another version.", bundle: .module,
                    comment: "Why a version is missing: the source's name")
            }
        return String(
            localized: "No \(names) this time. \(reason)", bundle: .module,
            comment: "Partial result banner: the missing versions, then why")
    }

    // MARK: Piece marks

    /// "Swapped" or "Added" for a piece that isn't in Simple (LR-05a.3), by piece ID. With
    /// `original`, the stylist's look before she changed it in Swap, a piece she swapped in is
    /// marked "Swapped" too, Simple included (Phase 11).
    static func changes(
        in look: Look, simple: Look?, original: Look? = nil, garments: [Garment.ID: Garment]
    ) -> [String: LookPieceChange] {
        var changes: [String: LookPieceChange] = [:]
        if look.version != .simple, let simple {
            let simpleKinds = Set(simple.garmentIDs.compactMap { garments[$0]?.category })
            for piece in look.pieces where !piece.isSameAsSimple && !piece.isIdea {
                guard let id = piece.garmentID, let category = garments[id]?.category else { continue }
                changes[piece.id.rawValue] = simpleKinds.contains(category) ? .swapped : .added
            }
        }
        if let original, original.id != look.id {
            let originalIDs = Set(original.garmentIDs)
            let originalKinds = Set(
                original.pieces.compactMap { piece in
                    piece.idea?.category ?? piece.garmentID.flatMap { garments[$0]?.category }
                })
            for piece in look.pieces {
                guard let id = piece.garmentID, !originalIDs.contains(id), let category = garments[id]?.category
                else { continue }
                changes[piece.id.rawValue] = originalKinds.contains(category) ? .swapped : .added
            }
        }
        return changes
    }

    /// Under the piece list once she changed the look with Swap a piece.
    static var changedByHer: String {
        String(
            localized: "You changed this look. Undo goes back one change.", bundle: .module,
            comment: "Your looks: under the pieces after a swap or removal (LR-08.2)")
    }

    // MARK: Saving

    /// The name a look gets when she saves it (LR-08): its main colours, such as "Pink & navy" or
    /// "Blue dress", with the version when it isn't Simple. She can rename it in Saved Looks.
    func name(for look: Look, garments: [Garment.ID: Garment]) -> String {
        Self.name(for: look, occasion: request.occasion, garments: garments, locale: locale)
    }

    /// The same name for a look on its own, such as an earlier result saved from Saved Looks'
    /// search (Phase 21c): its occasion stands in for the request's.
    static func name(
        for look: Look, occasion: Occasion?, garments: [Garment.ID: Garment], locale: Locale
    ) -> String {
        let pieces = look.garmentIDs.compactMap { garments[$0] }
        let base: String
        if let colours = Self.colourName(of: pieces, locale: locale) {
            base = colours
        } else if let occasion = occasion?.title {
            base = String(
                localized: "\(occasion) look", bundle: .module,
                comment: "Name of a saved look with no main colours: the occasion")
        } else {
            base = SavedLooksText.unnamed(occasion: nil)
        }
        switch look.version {
        case .dressedUp:
            return String(
                localized: "\(base), dressed up", bundle: .module, comment: "Name of a saved Dressed up look")
        case .somethingNew:
            return String(
                localized: "\(base), something new", bundle: .module, comment: "Name of a saved Something new look")
        case .simple, nil:
            return base
        }
    }

    /// A look's name from its main colours: "Blue dress", "Pink & navy", "All navy". `nil` when
    /// it has no dress and no coloured top and bottom.
    static func colourName(of pieces: [Garment], locale: Locale) -> String? {
        let colour = { (kind: GarmentCategory) in pieces.first { $0.category == kind }?.colors.first }
        if let dress = colour(.dress) {
            let dressWord = dress.title
            return String(
                localized: "\(dressWord) dress", bundle: .module, comment: "Name of a saved look: a dress's colour")
        }
        guard let top = colour(.top), let bottom = colour(.bottom) else { return nil }
        let topWord = top.title
        let bottomWord = bottom.title.lowercased(with: locale)
        return top == bottom
            ? String(
                localized: "All \(bottomWord)", bundle: .module,
                comment: "Name of a saved look whose top and bottom are one colour")
            : String(
                localized: "\(topWord) & \(bottomWord)", bundle: .module,
                comment: "Name of a saved look: the top's colour and the bottom's")
    }

    static var saved: String {
        String(localized: "Saved to Saved Looks", bundle: .module, comment: "Toast after Save look")
    }

    static var unsaved: String {
        String(localized: "Taken out of Saved Looks", bundle: .module, comment: "Toast after unsaving a look")
    }

    static var saveFailed: String {
        String(
            localized: "That look couldn’t be saved. Try again.", bundle: .module,
            comment: "Toast when saving a look fails")
    }

    static var undo: String {
        String(localized: "Undo", bundle: .module, comment: "Toast action")
    }

    // MARK: Saved tab

    /// Under the Saved tab: whose looks these are, and that opening them is free (LR-06.1).
    var savedLead: String {
        String(
            localized: "Looks you saved for \(occasionValue) from \(sourceName). Opening them sends nothing.",
            bundle: .module, comment: "Saved tab lead: the occasion and the source")
    }

    var savedEmptyTitle: String {
        String(localized: "No saved looks here yet", bundle: .module, comment: "Saved tab empty state title")
    }

    /// LR-06.2: how to save a look.
    var savedEmptyMessage: String {
        String(
            localized:
                "When you see a look you like on Today, tap Save look. Looks you save for \(occasionValue) from \(sourceName) show up here.",
            bundle: .module, comment: "Saved tab empty state: the occasion and the source")
    }
}

/// How a piece differs from Simple, marked in words in the piece list (LR-05a.3).
enum LookPieceChange: Hashable {
    /// It replaces a piece of the same kind in Simple.
    case swapped
    /// Simple has no piece of this kind.
    case added

    var title: String {
        switch self {
        case .swapped:
            String(localized: "Swapped", bundle: .module, comment: "Mark on a piece that replaces one in Simple")
        case .added: String(localized: "Added", bundle: .module, comment: "Mark on a piece Simple doesn't have")
        }
    }
}
