import Foundation
import Models
import Testing

/// What she types on Fit and measurements becomes a stored value, or a problem (PRD §10.1,
/// Phase 14a). All values here are made up.
struct MeasurementEntryTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    // MARK: Numbers

    @Test func plainNumbersAndBothDecimalMarks() {
        #expect(MeasurementEntry.number("26", locale: us) == 26)
        #expect(MeasurementEntry.number(" 26.5 ", locale: us) == 26.5)
        #expect(MeasurementEntry.number(".5", locale: us) == 0.5)
        // A comma is the decimal mark in Germany, and taken as one anywhere.
        #expect(MeasurementEntry.number("26,5", locale: germany) == 26.5)
        #expect(MeasurementEntry.number("26.5", locale: germany) == 26.5)
        #expect(MeasurementEntry.number("26,5", locale: us) == 26.5)
    }

    @Test(arguments: ["", " ", "abc", "-3", "+3", "1.2.3", "2 6", "26in", "1e3", "٢٦", ".", "123456789"])
    func thingsThatArentNumbers(_ text: String) {
        #expect(MeasurementEntry.number(text, locale: us) == nil)
    }

    // MARK: Lengths and weight

    @Test func anEmptyBoxMeansNoValueNotZero() throws {
        // PRD §10.2: unknown is absent, never zero.
        #expect(try MeasurementEntry.length("  ", for: .waist, in: .inches, locale: us) == nil)
        #expect(try MeasurementEntry.weight("", in: .pounds, locale: us) == nil)
        #expect(try MeasurementEntry.height(feet: "", inches: " ", locale: us) == nil)
    }

    @Test func aLengthKeepsTheUnitItWasTypedIn() throws {
        #expect(try MeasurementEntry.length("27", for: .waist, in: .inches, locale: us) == Length(27, .inches))
        #expect(
            try MeasurementEntry.length("68,5", for: .waist, in: .centimeters, locale: germany)
                == Length(68.5, .centimeters))
        #expect(try MeasurementEntry.weight("59", in: .kilograms, locale: us) == Weight(59, .kilograms))
    }

    @Test func outOfRangeAndNotANumber() throws {
        #expect(throws: EntryProblem.notANumber) {
            try MeasurementEntry.length("abc", for: .waist, in: .inches, locale: us)
        }
        #expect(throws: EntryProblem.outOfRange) {
            try MeasurementEntry.length("270", for: .waist, in: .inches, locale: us)
        }
        // 270 cm is about 106 inches, too long for an inseam; 70 cm is fine.
        #expect(throws: EntryProblem.outOfRange) {
            try MeasurementEntry.length("270", for: .inseam, in: .centimeters, locale: us)
        }
        #expect(try MeasurementEntry.length("70", for: .inseam, in: .centimeters, locale: us) != nil)
        #expect(throws: EntryProblem.outOfRange) { try MeasurementEntry.weight("0", in: .pounds, locale: us) }
        #expect(throws: EntryProblem.notANumber) { try MeasurementEntry.weight("-5", in: .pounds, locale: us) }
    }

    @Test func heightInFeetAndInches() throws {
        #expect(try MeasurementEntry.height(feet: "4", inches: "11", locale: us) == Length(59, .inches))
        #expect(try MeasurementEntry.height(feet: "5", inches: "", locale: us) == Length(60, .inches))
        #expect(try MeasurementEntry.height(feet: "5", inches: "2.5", locale: us) == Length(62.5, .inches))
        #expect(throws: EntryProblem.inchesPart) { try MeasurementEntry.height(feet: "4", inches: "12", locale: us) }
        #expect(throws: EntryProblem.notANumber) { try MeasurementEntry.height(feet: "4.5", inches: "", locale: us) }
        #expect(throws: EntryProblem.notANumber) { try MeasurementEntry.height(feet: "four", inches: "", locale: us) }
        // 11 inches alone and 9 feet are both outside the height range.
        #expect(throws: EntryProblem.outOfRange) { try MeasurementEntry.height(feet: "", inches: "11", locale: us) }
        #expect(throws: EntryProblem.outOfRange) { try MeasurementEntry.height(feet: "9", inches: "", locale: us) }
    }

    @Test func everyShownWholeNumberIsAccepted() throws {
        // The words under a box give a range in her units; both ends must save.
        for field in MeasurementField.allCases {
            for units in MeasurementUnits.allCases {
                let range = MeasurementEntry.shownRange(for: field, in: units)
                #expect(range.lowerBound < range.upperBound)
                for end in [range.lowerBound, range.upperBound] {
                    let text = String(end)
                    if field == .weight {
                        #expect(try MeasurementEntry.weight(text, in: units.weight, locale: us) != nil)
                    } else {
                        #expect(try MeasurementEntry.length(text, for: field, in: units.length, locale: us) != nil)
                    }
                }
            }
        }
        #expect(MeasurementEntry.shownRange(for: .waist, in: .imperial) == 15...70)
        #expect(MeasurementEntry.shownRange(for: .height, in: .metric) == 92...243)
        #expect(MeasurementEntry.shownRange(for: .weight, in: .metric) == 23...317)
    }

    // MARK: Units

    @Test func unitsFollowTheRegionUntilShePicks() {
        #expect(MeasurementUnits.preferred(for: us) == .imperial)
        #expect(MeasurementUnits.preferred(for: Locale(identifier: "en_GB")) == .imperial)
        #expect(MeasurementUnits.preferred(for: germany) == .metric)
        #expect(MeasurementUnits.preferred(for: Locale(identifier: "es_MX")) == .metric)
    }

    @Test func conversionsDontLoseTheStoredValue() {
        let height = Length(150, .centimeters)
        #expect(abs(height.inches - 59.055) < 0.001)
        #expect(height.value(in: .centimeters) == 150)
        #expect(abs(Length(59, .inches).centimeters - 149.86) < 0.001)
        let weight = Weight(130, .pounds)
        #expect(abs(weight.kilograms - 58.967) < 0.001)
        #expect(weight.value(in: .pounds) == 130)
        #expect(abs(Weight(59, .kilograms).value(in: .pounds) - 130.07) < 0.01)
    }

    // MARK: Fields

    @Test func settingAndClearingEachField() {
        var measurements = BodyMeasurements()
        for field in MeasurementField.allCases where field != .weight {
            measurements.set(Length(30, .inches), for: field)
            #expect(measurements.length(of: field) == Length(30, .inches))
            #expect(measurements.checkedValue(of: field) == 30)
        }
        measurements.weight = Weight(130, .pounds)
        #expect(measurements.checkedValue(of: .weight) == 130)
        #expect(measurements.length(of: .weight) == nil)
        for field in MeasurementField.allCases {
            measurements.clear(field)
        }
        #expect(measurements.isEmpty)
    }

    @Test func measurementsNeverPrintTheirValues() {
        // SECURITY_STANDARD §1: no Sensitive data in logs. A stray print or interpolation shows
        // no numbers, and dump finds no children.
        let measurements = BodyMeasurements(height: Length(59, .inches), weight: Weight(130, .pounds))
        let printed = ["\(measurements)", String(describing: measurements), String(reflecting: measurements)]
        for text in printed {
            #expect(!text.contains("59"))
            #expect(!text.contains("130"))
            #expect(text.contains("redacted"))
        }
        var dumped = ""
        dump(measurements, to: &dumped)
        #expect(!dumped.contains("59"))
        #expect(!dumped.contains("130"))
        #expect(Mirror(reflecting: measurements).children.isEmpty)
    }

    /// The parts print nothing either: a length, a weight, a fitting piece and her usual fit.
    @Test func fitDetailsNeverPrintTheirValues() {
        let piece = FitPiece(id: "f1", brand: "Old Navy", category: .bottom, sizeLabel: "0 Petite", result: .tooLong)
        let values: [(Any, [String])] = [
            (Length(59, .inches), ["59", "inches"]),
            (Weight(130, .pounds), ["130", "pounds"]),
            (piece, ["Old Navy", "Petite", "tooLong", "bottom"]),
            (Comfort.relaxed, ["relaxed"]),
        ]
        for (value, secrets) in values {
            var dumped = ""
            dump(value, to: &dumped)
            let printed = ["\(value)", String(describing: value), String(reflecting: value), dumped]
            for text in printed {
                for secret in secrets {
                    #expect(!text.contains(secret), "\(text) shows \(secret)")
                }
                #expect(text.contains("redacted"))
            }
            #expect(Mirror(reflecting: value).children.isEmpty)
        }
        // The word itself is still there for code that needs it.
        #expect(Comfort.relaxed.rawValue == "relaxed")
    }
}
