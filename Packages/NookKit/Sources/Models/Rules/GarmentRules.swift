import Foundation

/// A field on the Add a piece form that can be refused, in the order the form shows them.
public enum GarmentField: String, CaseIterable, Hashable, Sendable, Codable {
    case name
    case category
    case colorNote
    case brand
    case sizeLabel
    case notes
}

/// Why one field was refused.
public enum FieldProblem: Error, Hashable, Sendable {
    /// A required field is empty.
    case empty
    case tooLong(maximum: Int)
    /// Line breaks, tabs and other control characters aren't allowed in one-line fields.
    case controlCharacters
    /// A required choice (the kind of piece) hasn't been made.
    case missingChoice
}

/// Every refused field of a piece, so the form can show each problem by its field at once.
public struct GarmentProblems: Error, Hashable, Sendable {
    public var byField: [GarmentField: FieldProblem]

    public init(_ byField: [GarmentField: FieldProblem] = [:]) {
        self.byField = byField
    }

    public var isEmpty: Bool { byField.isEmpty }

    /// The refused fields in form order, so the first one is the one to move to.
    public var fields: [GarmentField] { GarmentField.allCases.filter { byField[$0] != nil } }

    public subscript(field: GarmentField) -> FieldProblem? { byField[field] }
}

/// Checks for what she types about a piece (Add a piece and Edit, Phase 7b).
///
/// Only a name and a kind are required. The other text fields are optional and only have length
/// limits, so a typo or a pasted page can't fill the store. The limits are about storage and
/// layout, not style: nothing here says what she should wear.
public enum GarmentRules {
    public static let colorNoteMaximum = 40
    public static let brandMaximum = 40
    public static let sizeLabelMaximum = 20
    /// Notes are bounded like the free text a styling request may carry (DATA_MAP.md).
    public static let notesMaximum = 2_000
    /// "Describe it in words" (by-words add).
    public static let descriptionMaximum = 1_000

    /// Every problem with these details. Empty when they can be saved.
    public static func problems(in details: GarmentDetails) -> GarmentProblems {
        do {
            _ = try checked(details)
            return GarmentProblems()
        } catch {
            return error
        }
    }

    /// The details with every text field trimmed, ready to save.
    ///
    /// - Throws: every refused field at once, not only the first.
    public static func checked(_ details: GarmentDetails) throws(GarmentProblems) -> GarmentDetails {
        var problems: [GarmentField: FieldProblem] = [:]
        var details = details
        do {
            details.name = try NameRules.garmentName(details.name)
        } catch {
            problems[.name] = fieldProblem(error)
        }
        if details.category == nil { problems[.category] = .missingChoice }
        record(&details.colorNote, maximum: colorNoteMaximum, field: .colorNote, in: &problems)
        record(&details.brand, maximum: brandMaximum, field: .brand, in: &problems)
        record(&details.sizeLabel, maximum: sizeLabelMaximum, field: .sizeLabel, in: &problems)
        details.notes = details.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if details.notes.count > notesMaximum { problems[.notes] = .tooLong(maximum: notesMaximum) }
        if !problems.isEmpty { throw GarmentProblems(problems) }
        return details
    }

    /// The words she typed to describe a piece, trimmed. Empty isn't refused here; the screen just
    /// has nothing to suggest from.
    public static func description(_ text: String) throws(FieldProblem) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > descriptionMaximum { throw .tooLong(maximum: descriptionMaximum) }
        return text
    }

    /// The text-field problems of a stored garment (its kind is always set). Stores call this on
    /// every save.
    public static func problems(in garment: Garment) -> GarmentProblems {
        problems(in: GarmentDetails(garment))
    }

    // MARK: Helpers

    /// An optional one-line field: trimmed, empty allowed, a length limit and no control characters.
    private static func record(
        _ text: inout String,
        maximum: Int,
        field: GarmentField,
        in problems: inout [GarmentField: FieldProblem]
    ) {
        do {
            text = try NameRules.checked(text, maximum: maximum, allowsEmpty: true)
        } catch {
            problems[field] = fieldProblem(error)
        }
    }

    private static func fieldProblem(_ problem: NameProblem) -> FieldProblem {
        switch problem {
        case .empty: .empty
        case .tooLong(let maximum): .tooLong(maximum: maximum)
        case .controlCharacters: .controlCharacters
        // Garments have no uniqueness rule; two pieces may share a name.
        case .duplicate: .empty
        }
    }
}
