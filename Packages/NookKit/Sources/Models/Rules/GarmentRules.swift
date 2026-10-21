import Foundation

/// A field on the Add a piece form that can be refused, in the order the form shows them.
public enum GarmentField: String, CaseIterable, Hashable, Sendable, Codable {
    case name
    /// "Other names" (Phase 21c): the name being added, or the list as a whole.
    case otherNames
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
    /// The same as a name the piece already has (other names, Phase 21c).
    case duplicate
    /// A list is full (other names, Phase 21c).
    case tooMany(maximum: Int)
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
    /// Each of a piece's other names (PRD §7.6), as long as a shade name or brand.
    public static let otherNameMaximum = 40
    /// How many other names one piece keeps. Enough for her nicknames, and it keeps search fast.
    public static let otherNamesMaximumCount = 10
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
        do {
            details.otherNames = try otherNames(details.otherNames, name: details.name)
        } catch {
            problems[.otherNames] = error
        }
        if details.category == nil { problems[.category] = .missingChoice }
        // A type belongs to one kind. One left from another kind (she changed the kind) goes.
        if let subKind = details.subKind, subKind.category != details.category { details.subKind = nil }
        record(&details.colorNote, maximum: colorNoteMaximum, field: .colorNote, in: &problems)
        record(&details.brand, maximum: brandMaximum, field: .brand, in: &problems)
        record(&details.sizeLabel, maximum: sizeLabelMaximum, field: .sizeLabel, in: &problems)
        details.notes = details.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if details.notes.count > notesMaximum { problems[.notes] = .tooLong(maximum: notesMaximum) }
        if !problems.isEmpty { throw GarmentProblems(problems) }
        return details
    }

    /// A piece's other names, ready to keep: each trimmed and checked like a shade name, empty
    /// ones dropped, and repeats dropped, including the piece's own name. Repeats ignore case
    /// and accents, so "Date-night top" and "date-night TOP" are one name.
    ///
    /// - Throws: `tooLong` or `controlCharacters` for a name that can't be kept, or `tooMany`
    ///   when more than `otherNamesMaximumCount` are left.
    public static func otherNames(_ names: [String], name: String) throws(FieldProblem) -> [String] {
        var kept: [String] = []
        var seen: Set<String> = [searchKey(name)]
        for text in names {
            let other: String
            do {
                other = try NameRules.checked(text, maximum: otherNameMaximum, allowsEmpty: true)
            } catch {
                throw fieldProblem(error)
            }
            guard !other.isEmpty, seen.insert(searchKey(other)).inserted else { continue }
            kept.append(other)
        }
        if kept.count > otherNamesMaximumCount { throw .tooMany(maximum: otherNamesMaximumCount) }
        return kept
    }

    /// One more other name for the form's Add: trimmed and checked, and refused when it's empty,
    /// already one of the piece's names, or the list is full.
    public static func newOtherName(_ text: String, adding details: GarmentDetails) throws(FieldProblem) -> String {
        let other: String
        do {
            other = try NameRules.checked(text, maximum: otherNameMaximum, allowsEmpty: false)
        } catch {
            throw fieldProblem(error)
        }
        let key = searchKey(other)
        if key == searchKey(details.name) || details.otherNames.contains(where: { searchKey($0) == key }) {
            throw .duplicate
        }
        if details.otherNames.count >= otherNamesMaximumCount { throw .tooMany(maximum: otherNamesMaximumCount) }
        return other
    }

    /// How two names are compared: trimmed, ignoring case and accents.
    private static func searchKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
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
