import Foundation
import Models

/// The words Add a piece and Edit show: field names, problems and suggestions.
enum GarmentEditorText {
    // MARK: Fields

    static func label(for field: GarmentField) -> String {
        switch field {
        case .name: String(localized: "Name", bundle: .module, comment: "Add a piece: field label")
        case .otherNames:
            String(
                localized: "Other names", bundle: .module,
                comment: "Add a piece: field label, more names search finds the piece by")
        case .category:
            String(localized: "Kind", bundle: .module, comment: "Add a piece: field label, the kind of piece")
        case .colorNote:
            String(
                localized: "Shade name", bundle: .module, comment: "Add a piece: field label, her word for the shade")
        case .brand: String(localized: "Brand", bundle: .module, comment: "Add a piece: field label")
        case .sizeLabel:
            String(localized: "Size on the label", bundle: .module, comment: "Add a piece: field label")
        case .notes: String(localized: "Notes", bundle: .module, comment: "Add a piece: field label, her own notes")
        }
    }

    /// "Type", the field under Kind with Cardigan, Blazer and the like (Phase 21c).
    static var subKindLabel: String {
        String(
            localized: "Type", bundle: .module,
            comment: "Add a piece: field label, the type within the kind, like Cardigan")
    }

    /// The type chip for none of the listed types.
    static var noSubKind: String {
        String(
            localized: "None of these", bundle: .module,
            comment: "Add a piece: type chip when none of the listed types fits, or she'd rather not say")
    }

    /// Under the other names: what they're for.
    static var otherNamesNote: String {
        String(
            localized: "Search finds the piece by any of its names.", bundle: .module,
            comment: "Add a piece: under Other names")
    }

    /// Spoken on an other name's chip, which removes it: "Remove Date-night top".
    static func removeOtherName(_ name: String) -> String {
        String(
            localized: "Remove \(name)", bundle: .module,
            comment: "VoiceOver label of the chip that removes one of the piece's other names")
    }

    /// What's wrong with a field, in words that say how to fix it.
    static func problem(_ problem: FieldProblem, in field: GarmentField) -> String {
        switch (field, problem) {
        case (.name, .empty):
            return String(localized: "Give it a name.", bundle: .module, comment: "Add a piece: the name is empty")
        case (.category, _):
            return String(
                localized: "Choose what kind of piece it is.", bundle: .module,
                comment: "Add a piece: no kind of piece chosen")
        case (.otherNames, .empty):
            return String(
                localized: "Type a name first.", bundle: .module,
                comment: "Add a piece: Add under Other names with nothing typed")
        case (_, .duplicate):
            return String(
                localized: "It already has that name.", bundle: .module,
                comment: "Add a piece: the other name is the same as its name or another of its names")
        case (_, .tooMany(let maximum)):
            return String(
                localized: "A piece can have up to \(maximum) other names. Remove one to add another.", bundle: .module,
                comment: "Add a piece: the piece has as many other names as it can keep, with the limit")
        case (_, .tooLong(let maximum)):
            return String(
                localized: "Keep this to \(maximum) characters.", bundle: .module,
                comment: "Add a piece: a field is too long, with the limit")
        case (_, .controlCharacters):
            return String(
                localized: "Keep this on one line.", bundle: .module,
                comment: "Add a piece: a one-line field has a line break in it")
        case (_, .empty), (_, .missingChoice):
            return String(localized: "Fill this in.", bundle: .module, comment: "Add a piece: a field is empty")
        }
    }

    /// What VoiceOver says when Save finds problems: which fields to check.
    static func problemsAnnouncement(_ problems: GarmentProblems) -> String {
        let fields = problems.fields.map(label(for:)).formatted(.list(type: .and))
        return String(
            localized: "Not saved yet. Check \(fields).", bundle: .module,
            comment: "VoiceOver, after Save found problems, with the fields to check, like Name and Kind")
    }

    // MARK: Suggestions

    /// The suggestion's field: "Name", "Kind", "Colour".
    static func suggestionLabel(_ suggestion: GarmentSuggestion) -> String {
        switch suggestion {
        case .name: label(for: .name)
        case .category: label(for: .category)
        case .colors: String(localized: "Colour", bundle: .module, comment: "Add a piece: field label")
        case .fit: String(localized: "Fit", bundle: .module, comment: "Add a piece: field label, how it's cut")
        case .dressiness: String(localized: "How dressy", bundle: .module, comment: "Add a piece: field label")
        case .warmth: String(localized: "How warm", bundle: .module, comment: "Add a piece: field label")
        case .seasons: String(localized: "Seasons", bundle: .module, comment: "Add a piece: field label")
        case .occasions: String(localized: "Occasions", bundle: .module, comment: "Add a piece: field label")
        case .brand: label(for: .brand)
        case .detail:
            String(localized: "Detail", bundle: .module, comment: "Add a piece: a suggested detail for her notes")
        }
    }

    /// The suggested value: "Sage cardigan", "Layers", "Green · Sage".
    static func suggestionValue(_ suggestion: GarmentSuggestion) -> String {
        switch suggestion {
        case .name(let name): name
        case .category(let category): category.chipTitle
        case .colors(let colors, let note):
            ([colors.map(\.title).formatted(.list(type: .and))] + [note].compactMap { $0 }).joined(separator: " · ")
        case .fit(let fit): fit.title
        case .dressiness(let dressiness): dressiness.title
        case .warmth(let warmth): warmth.title
        case .seasons(let seasons): Season.allCases.filter(seasons.contains).map(\.title).formatted(.list(type: .and))
        case .occasions(let occasions):
            Occasion.allCases.filter(occasions.contains).map(\.title).formatted(.list(type: .and))
        case .brand(let brand): brand
        case .detail(let detail): detail
        }
    }
}
