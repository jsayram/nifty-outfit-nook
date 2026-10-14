import Foundation
import Models

/// The words Add a piece and Edit show: field names, problems and suggestions.
enum GarmentEditorText {
    // MARK: Fields

    static func label(for field: GarmentField) -> String {
        switch field {
        case .name: String(localized: "Name", bundle: .module, comment: "Add a piece: field label")
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

    /// What's wrong with a field, in words that say how to fix it.
    static func problem(_ problem: FieldProblem, in field: GarmentField) -> String {
        switch (field, problem) {
        case (.name, .empty):
            return String(localized: "Give it a name.", bundle: .module, comment: "Add a piece: the name is empty")
        case (.category, _):
            return String(
                localized: "Choose what kind of piece it is.", bundle: .module,
                comment: "Add a piece: no kind of piece chosen")
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
