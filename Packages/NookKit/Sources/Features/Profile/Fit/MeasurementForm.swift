import Foundation
import Models

/// What the measurement sheet holds while she types: one box, or feet and inches for a height in
/// inches. Turning it into a stored value goes through `MeasurementEntry`, so the sheet, the
/// tests and the store all check the same way.
nonisolated struct MeasurementForm: Hashable, Identifiable, Sendable {
    let field: MeasurementField
    let units: MeasurementUnits
    /// The one box (every field but an imperial height).
    var text = ""
    /// Imperial height's two boxes.
    var feet = ""
    var inches = ""
    /// True when the field had a value as the sheet opened, so Clear is offered.
    let hadValue: Bool

    var id: MeasurementField { field }

    /// Height in inches is typed as feet and inches; everything else in one box.
    var usesFeetAndInches: Bool { field == .height && units == .imperial }

    /// A value she typed, ready for the store.
    enum Value: Hashable, Sendable {
        case length(Length?)
        case weight(Weight?)
    }

    /// A form opened on a field, with its stored value in her units.
    init(field: MeasurementField, measurements: BodyMeasurements, units: MeasurementUnits, locale: Locale) {
        self.field = field
        self.units = units
        let stored: Double? =
            field == .weight
            ? measurements.weight?.value(in: units.weight)
            : measurements.length(of: field)?.value(in: units.length)
        hadValue = stored != nil
        guard let stored else { return }
        if usesFeetAndInches {
            let parts = MeasurementFormat.split(stored)
            feet = MeasurementFormat.number(parts.feet, locale: locale)
            inches = MeasurementFormat.number(parts.inches, locale: locale)
        } else {
            text = MeasurementFormat.boxText(stored, field: field, units: units, locale: locale)
        }
    }

    /// The value she typed, or the problem with it. Empty boxes mean "no value", never zero.
    func value(locale: Locale) throws(EntryProblem) -> Value {
        if field == .weight {
            return .weight(try MeasurementEntry.weight(text, in: units.weight, locale: locale))
        }
        if usesFeetAndInches {
            return .length(try MeasurementEntry.height(feet: feet, inches: inches, locale: locale))
        }
        return .length(try MeasurementEntry.length(text, for: field, in: units.length, locale: locale))
    }
}
