import Foundation

/// Why a name was refused.
public enum NameProblem: Error, Hashable, Sendable {
    case empty
    case tooLong(maximum: Int)
    /// Line breaks, tabs and other control characters aren't allowed in names.
    case controlCharacters
    /// Another suitcase already has this name (ignoring case).
    case duplicate
}

/// Checks for the names she types. Each check trims spaces and returns the name to store.
public enum NameRules {
    public static let signNameMaximum = 20
    public static let garmentNameMaximum = 60
    public static let lookNameMaximum = 60
    public static let suitcaseNameMaximum = 40

    /// Name on your sign (RD-03). Empty is allowed: the sign shows a neutral fallback.
    public static func signName(_ text: String) throws(NameProblem) -> String {
        try checked(text, maximum: signNameMaximum, allowsEmpty: true)
    }

    public static func garmentName(_ text: String) throws(NameProblem) -> String {
        try checked(text, maximum: garmentNameMaximum, allowsEmpty: false)
    }

    /// Looks are named when saved (LR-08).
    public static func lookName(_ text: String) throws(NameProblem) -> String {
        try checked(text, maximum: lookNameMaximum, allowsEmpty: false)
    }

    /// A suitcase name must be unique among her suitcases, ignoring case.
    ///
    /// - Parameter renaming: the suitcase being renamed, so its own name doesn't count as a clash.
    public static func suitcaseName(
        _ text: String,
        among suitcases: [Suitcase],
        renaming: Suitcase.ID? = nil
    ) throws(NameProblem) -> String {
        let name = try checked(text, maximum: suitcaseNameMaximum, allowsEmpty: false)
        let clash = suitcases.contains { suitcase in
            suitcase.id != renaming && suitcase.name.compare(name, options: [.caseInsensitive]) == .orderedSame
        }
        if clash { throw .duplicate }
        return name
    }

    static func checked(_ text: String, maximum: Int, allowsEmpty: Bool) throws(NameProblem) -> String {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty && !allowsEmpty { throw .empty }
        if name.count > maximum { throw .tooLong(maximum: maximum) }
        if name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw .controlCharacters
        }
        return name
    }
}

/// A measurement value that was refused.
public struct MeasurementProblem: Hashable, Sendable {
    public var field: MeasurementField
    /// The accepted range, in inches for lengths and pounds for weight.
    public var allowed: ClosedRange<Double>

    public init(field: MeasurementField, allowed: ClosedRange<Double>) {
        self.field = field
        self.allowed = allowed
    }
}

public enum MeasurementField: String, CaseIterable, Hashable, Sendable {
    case height
    case waist
    case bust
    case hips
    case inseam
    case weight
}

/// Sanity checks for the fit fields she types in (PRD §10.1).
///
/// These only catch typing mistakes and impossible values. They say nothing about fit, and an
/// empty field is always fine.
public enum MeasurementRules {
    /// Accepted ranges, in inches (lengths) and pounds (weight).
    public static func allowedRange(for field: MeasurementField) -> ClosedRange<Double> {
        switch field {
        case .height: 36...96
        case .waist: 15...70
        case .bust: 20...70
        case .hips: 20...80
        case .inseam: 15...45
        case .weight: 50...700
        }
    }

    /// Every filled-in value that is not a number or is out of range. Empty means all good.
    public static func problems(in measurements: BodyMeasurements) -> [MeasurementProblem] {
        let values: [(MeasurementField, Double?)] = [
            (.height, measurements.height?.inches),
            (.waist, measurements.waist?.inches),
            (.bust, measurements.bust?.inches),
            (.hips, measurements.hips?.inches),
            (.inseam, measurements.inseam?.inches),
            (.weight, measurements.weight?.pounds),
        ]
        return values.compactMap { field, value in
            guard let value else { return nil }
            let allowed = allowedRange(for: field)
            return value.isFinite && allowed.contains(value) ? nil : MeasurementProblem(field: field, allowed: allowed)
        }
    }

    /// A fit piece needs a brand and a size label (LR-13).
    public static func checkedFitPiece(_ piece: FitPiece) throws(NameProblem) -> FitPiece {
        var piece = piece
        piece.brand = try NameRules.checked(piece.brand, maximum: 40, allowsEmpty: false)
        piece.sizeLabel = try NameRules.checked(piece.sizeLabel, maximum: 20, allowsEmpty: false)
        return piece
    }
}
