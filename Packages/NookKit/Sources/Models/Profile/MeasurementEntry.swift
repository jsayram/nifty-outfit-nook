import Foundation

/// The units Fit and measurements shows and takes: inches and pounds, or centimetres and
/// kilograms (`fit.html`, "in · lb" and "cm · kg").
///
/// Values keep the unit she typed them in (`Length`, `Weight`), so switching units only changes
/// how they're shown and never rounds what's stored.
///
/// Data tier: **Personal** (a display choice).
public enum MeasurementUnits: String, CaseIterable, Hashable, Sendable, Codable {
    /// Inches and pounds.
    case imperial
    /// Centimetres and kilograms.
    case metric

    /// The units to start with before she picks: metric where the region measures in metres,
    /// inches and pounds in the US and the UK (where people still give body sizes in inches).
    public static func preferred(for locale: Locale) -> MeasurementUnits {
        locale.measurementSystem == .metric ? .metric : .imperial
    }

    public var length: Length.Unit {
        switch self {
        case .imperial: .inches
        case .metric: .centimeters
        }
    }

    public var weight: Weight.Unit {
        switch self {
        case .imperial: .pounds
        case .metric: .kilograms
        }
    }
}

extension Length {
    public var centimeters: Double {
        switch unit {
        case .inches: value * 2.54
        case .centimeters: value
        }
    }

    /// The value in `unit`, unrounded.
    public func value(in unit: Unit) -> Double {
        switch unit {
        case .inches: inches
        case .centimeters: centimeters
        }
    }
}

extension Weight {
    public var kilograms: Double {
        switch unit {
        case .pounds: value / 2.204_622_6
        case .kilograms: value
        }
    }

    /// The value in `unit`, unrounded.
    public func value(in unit: Unit) -> Double {
        switch unit {
        case .pounds: pounds
        case .kilograms: kilograms
        }
    }
}

extension BodyMeasurements {
    /// A field's value in inches (lengths) or pounds (weight), the units `MeasurementRules`
    /// checks in. `nil` when it's empty.
    public func checkedValue(of field: MeasurementField) -> Double? {
        switch field {
        case .height: height?.inches
        case .waist: waist?.inches
        case .bust: bust?.inches
        case .hips: hips?.inches
        case .inseam: inseam?.inches
        case .weight: weight?.pounds
        }
    }

    /// A length field's value, or `nil` for weight and for an empty field.
    public func length(of field: MeasurementField) -> Length? {
        switch field {
        case .height: height
        case .waist: waist
        case .bust: bust
        case .hips: hips
        case .inseam: inseam
        case .weight: nil
        }
    }

    /// Sets a length field. Weight has its own property.
    public mutating func set(_ length: Length?, for field: MeasurementField) {
        switch field {
        case .height: height = length
        case .waist: waist = length
        case .bust: bust = length
        case .hips: hips = length
        case .inseam: inseam = length
        case .weight: break
        }
    }

    /// Empties one field.
    public mutating func clear(_ field: MeasurementField) {
        if field == .weight {
            weight = nil
        } else {
            set(nil, for: field)
        }
    }
}

/// Why a typed measurement was refused. The screen turns it into words with the range in her
/// units.
public enum EntryProblem: Error, Hashable, Sendable {
    /// Not a plain number: letters, a minus sign, two decimal points.
    case notANumber
    /// A number, but outside `MeasurementRules.allowedRange` for the field.
    case outOfRange
    /// Imperial height's inches part, which goes from 0 to under 12.
    case inchesPart
}

/// Turns what she types on Fit and measurements into stored values (PRD §10.1).
///
/// Every field is optional: empty text means "leave it empty", never zero (PRD §10.2, unknown is
/// absent). Numbers take the region's decimal separator or a point, so "26,5" and "26.5" both
/// work in Germany. The ranges are `MeasurementRules`', which only catch typing mistakes.
public enum MeasurementEntry {
    /// The longest text taken as a number. Body measurements never need more.
    static let maximumLength = 8

    /// A plain positive number, or `nil` when it isn't one. Spaces around it are fine; a sign,
    /// letters, grouping and a second decimal point are not.
    public static func number(_ text: String, locale: Locale) -> Double? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maximumLength else { return nil }
        if let separator = locale.decimalSeparator, separator != "." {
            text = text.replacing(separator, with: ".")
        }
        text = text.replacing(",", with: ".")
        let digits = text.filter(\.isASCII)
        guard digits == text, text.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.contains(where: { !$0.isEmpty }) else { return nil }
        return Double(text.hasPrefix(".") ? "0" + text : text)
    }

    /// A length field from one box, in `unit`. `nil` when the box is empty.
    public static func length(
        _ text: String, for field: MeasurementField, in unit: Length.Unit, locale: Locale
    ) throws(EntryProblem) -> Length? {
        guard !isBlank(text) else { return nil }
        guard let value = number(text, locale: locale) else { throw .notANumber }
        let length = Length(value, unit)
        try check(length.inches, field)
        return length
    }

    /// Height in feet and inches, from two boxes. Both empty means no height; one empty counts
    /// as zero, so "5" feet and an empty inches box is 5′ 0″.
    public static func height(feet: String, inches: String, locale: Locale) throws(EntryProblem) -> Length? {
        guard !isBlank(feet) || !isBlank(inches) else { return nil }
        let wholeFeet: Double
        if isBlank(feet) {
            wholeFeet = 0
        } else {
            guard let value = number(feet, locale: locale), value == value.rounded() else { throw .notANumber }
            wholeFeet = value
        }
        let extraInches: Double
        if isBlank(inches) {
            extraInches = 0
        } else {
            guard let value = number(inches, locale: locale) else { throw .notANumber }
            guard value < 12 else { throw .inchesPart }
            extraInches = value
        }
        let length = Length(wholeFeet * 12 + extraInches, .inches)
        try check(length.inches, .height)
        return length
    }

    /// Weight from one box, in `unit`. `nil` when the box is empty.
    public static func weight(_ text: String, in unit: Weight.Unit, locale: Locale) throws(EntryProblem) -> Weight? {
        guard !isBlank(text) else { return nil }
        guard let value = number(text, locale: locale) else { throw .notANumber }
        let weight = Weight(value, unit)
        try check(weight.pounds, .weight)
        return weight
    }

    /// The accepted range in `units`, rounded inwards to whole numbers, for the words under the
    /// box ("between 15 and 45 inches"). Any whole number shown is accepted.
    public static func shownRange(for field: MeasurementField, in units: MeasurementUnits) -> ClosedRange<Int> {
        let allowed = MeasurementRules.allowedRange(for: field)
        let factor: Double
        switch units {
        case .imperial: factor = 1
        case .metric: factor = field == .weight ? 1 / 2.204_622_6 : 2.54
        }
        let lower = Int((allowed.lowerBound * factor).rounded(.up))
        let upper = Int((allowed.upperBound * factor).rounded(.down))
        return lower...upper
    }

    private static func check(_ value: Double, _ field: MeasurementField) throws(EntryProblem) {
        guard value.isFinite, MeasurementRules.allowedRange(for: field).contains(value) else {
            throw .outOfRange
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
