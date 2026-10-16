import Foundation
import Models

/// How Fit and measurements writes a value, in her units and her region's number style.
///
/// Inches and pounds are shown to the nearest half inch and whole pound, centimetres to the
/// nearest whole centimetre and kilograms to one decimal place. Height in inches reads as feet
/// and inches, "4′ 11″". Each value also has a spoken form for VoiceOver ("4 feet 11 inches",
/// "66 centimetres"), so a symbol is never all it hears.
nonisolated enum MeasurementFormat {
    struct Shown: Hashable {
        let text: String
        let spoken: String
    }

    /// A field's value, or `nil` when it's empty.
    static func shown(
        _ field: MeasurementField, in measurements: BodyMeasurements, units: MeasurementUnits, locale: Locale
    ) -> Shown? {
        if field == .weight {
            return measurements.weight.map { weight(of: $0, units: units, locale: locale) }
        }
        guard let length = measurements.length(of: field) else { return nil }
        if field == .height, units == .imperial {
            return feetAndInches(length.inches, locale: locale)
        }
        return self.length(length, units: units, locale: locale)
    }

    static func length(_ length: Length, units: MeasurementUnits, locale: Locale) -> Shown {
        switch units {
        case .imperial:
            let inches = halves(length.inches)
            return Shown(
                text: format(Measurement(value: inches, unit: UnitLength.inches), width: .abbreviated, locale),
                spoken: format(Measurement(value: inches, unit: UnitLength.inches), width: .wide, locale))
        case .metric:
            let centimeters = length.centimeters.rounded()
            return Shown(
                text: format(
                    Measurement(value: centimeters, unit: UnitLength.centimeters), width: .abbreviated, locale),
                spoken: format(Measurement(value: centimeters, unit: UnitLength.centimeters), width: .wide, locale))
        }
    }

    static func weight(of weight: Weight, units: MeasurementUnits, locale: Locale) -> Shown {
        switch units {
        case .imperial:
            let pounds = weight.pounds.rounded()
            return Shown(
                text: format(Measurement(value: pounds, unit: UnitMass.pounds), width: .abbreviated, locale),
                spoken: format(Measurement(value: pounds, unit: UnitMass.pounds), width: .wide, locale))
        case .metric:
            let kilograms = (weight.kilograms * 10).rounded() / 10
            return Shown(
                text: format(Measurement(value: kilograms, unit: UnitMass.kilograms), width: .abbreviated, locale),
                spoken: format(Measurement(value: kilograms, unit: UnitMass.kilograms), width: .wide, locale))
        }
    }

    /// "4′ 11″", spoken "4 feet 11 inches".
    static func feetAndInches(_ totalInches: Double, locale: Locale) -> Shown {
        let parts = split(totalInches)
        let feet = number(parts.feet, locale: locale)
        let inches = number(parts.inches, locale: locale)
        let spokenFeet = format(Measurement(value: parts.feet, unit: UnitLength.feet), width: .wide, locale)
        let spokenInches = format(Measurement(value: parts.inches, unit: UnitLength.inches), width: .wide, locale)
        return Shown(
            text: String(
                localized: "\(feet)′ \(inches)″", bundle: .module,
                comment: "A height in feet and inches, like 4′ 11″. Keep the prime marks."),
            spoken: "\(spokenFeet) \(spokenInches)")
    }

    /// Whole feet and the inches left, to the nearest half inch.
    static func split(_ totalInches: Double) -> (feet: Double, inches: Double) {
        let rounded = halves(totalInches)
        let feet = (rounded / 12).rounded(.down)
        return (feet, rounded - feet * 12)
    }

    /// A number for a box: up to one decimal place, the region's decimal separator, no grouping.
    static func number(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
    }

    /// What a box shows when it opens: the stored value in her units, ready to edit.
    static func boxText(_ value: Double, field: MeasurementField, units: MeasurementUnits, locale: Locale) -> String {
        switch (field, units) {
        case (.weight, .imperial): number(value.rounded(), locale: locale)
        case (.weight, .metric): number((value * 10).rounded() / 10, locale: locale)
        case (_, .imperial): number(halves(value), locale: locale)
        case (_, .metric): number(value.rounded(), locale: locale)
        }
    }

    private static func halves(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    private static func format<UnitType: Dimension>(
        _ measurement: Measurement<UnitType>, width: Measurement<UnitType>.FormatStyle.UnitWidth, _ locale: Locale
    ) -> String {
        measurement.formatted(
            .measurement(width: width, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale))
    }
}
