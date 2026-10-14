import Foundation
import Models
import Testing

struct NameRulesTests {
    @Test func trimsSpaces() throws {
        #expect(try NameRules.garmentName("  Cute pink shirt \n") == "Cute pink shirt")
    }

    @Test func garmentAndLookNamesCantBeEmpty() {
        #expect(throws: NameProblem.empty) { try NameRules.garmentName("   ") }
        #expect(throws: NameProblem.empty) { try NameRules.lookName("") }
    }

    @Test func theSignNameMayBeEmpty() throws {
        // RD-03.2: the sign shows a neutral fallback instead.
        #expect(try NameRules.signName("  ") == "")
        #expect(try NameRules.signName("Lily") == "Lily")
    }

    @Test func namesHaveAMaximumLength() throws {
        #expect(throws: NameProblem.tooLong(maximum: 20)) { try NameRules.signName(String(repeating: "a", count: 21)) }
        #expect(try NameRules.signName(String(repeating: "a", count: 20)).count == 20)
        #expect(throws: NameProblem.tooLong(maximum: 60)) {
            try NameRules.garmentName(String(repeating: "b", count: 61))
        }
    }

    @Test func lengthCountsCharactersNotBytes() throws {
        #expect(try NameRules.signName(String(repeating: "é", count: 20)).count == 20)
    }

    @Test func controlCharactersAreRefused() {
        #expect(throws: NameProblem.controlCharacters) { try NameRules.garmentName("Pink\u{0}shirt") }
        #expect(throws: NameProblem.controlCharacters) { try NameRules.lookName("Two\nlines") }
    }

    @Test func suitcaseNamesAreUniqueIgnoringCase() throws {
        let suitcases = [Suitcase(id: "s-1", name: "Weekend", createdAt: TestTime.now)]
        #expect(throws: NameProblem.duplicate) { try NameRules.suitcaseName(" weekend ", among: suitcases) }
        #expect(try NameRules.suitcaseName("WEEKEND", among: suitcases, renaming: "s-1") == "WEEKEND")
        #expect(try NameRules.suitcaseName("Beach", among: suitcases) == "Beach")
    }
}

struct MeasurementRulesTests {
    @Test func emptyMeasurementsAreFine() {
        #expect(MeasurementRules.problems(in: BodyMeasurements()).isEmpty)
    }

    @Test func plausibleValuesPass() {
        let measurements = BodyMeasurements(
            height: Length(160, .centimeters),
            waist: Length(28, .inches),
            inseam: Length(27, .inches),
            weight: Weight(55, .kilograms)
        )
        #expect(MeasurementRules.problems(in: measurements).isEmpty)
    }

    @Test func impossibleValuesAreRefused() {
        let measurements = BodyMeasurements(
            height: Length(600, .inches),
            waist: Length(-3, .inches),
            bust: Length(.nan, .centimeters),
            weight: Weight(0, .pounds)
        )
        #expect(MeasurementRules.problems(in: measurements).map(\.field) == [.height, .waist, .bust, .weight])
    }

    @Test func centimetresAreCheckedInInches() {
        // 100 cm is about 39 inches, a possible inseam; 130 cm is about 51 inches, which isn't.
        #expect(MeasurementRules.problems(in: BodyMeasurements(inseam: Length(100, .centimeters))).isEmpty)
        let problems = MeasurementRules.problems(in: BodyMeasurements(inseam: Length(130, .centimeters)))
        #expect(problems == [MeasurementProblem(field: .inseam, allowed: 15...45)])
    }

    @Test func aFitPieceNeedsABrandAndSize() throws {
        let piece = FitPiece(id: "f-1", brand: " Example Co. ", category: .bottom, sizeLabel: "S")
        #expect(try MeasurementRules.checkedFitPiece(piece).brand == "Example Co.")
        var noSize = piece
        noSize.sizeLabel = " "
        #expect(throws: NameProblem.empty) { try MeasurementRules.checkedFitPiece(noSize) }
    }
}
