import Foundation
import Models
import NookTestSupport
import Testing

/// Other names and types on garments (Phase 21c, PRD §7.6): the rules, the store's check, and
/// search in Closet and Saved Looks.
struct OtherNamesTests {
    // MARK: Rules

    @Test func otherNamesAreTrimmedAndRepeatsDropped() throws {
        let names = try GarmentRules.otherNames(
            ["  Date-night top ", "", "date-night TOP", "Café top", "Cafe TOP", "Pink blouse"], name: "Pink blouse")
        #expect(names == ["Date-night top", "Café top"])
    }

    @Test func otherNamesHaveLimits() throws {
        let long = String(repeating: "a", count: GarmentRules.otherNameMaximum)
        #expect(try GarmentRules.otherNames([long], name: "Top") == [long])
        #expect(throws: FieldProblem.tooLong(maximum: 40)) {
            try GarmentRules.otherNames([long + "a"], name: "Top")
        }
        #expect(throws: FieldProblem.controlCharacters) {
            try GarmentRules.otherNames(["Two\nlines"], name: "Top")
        }
        let ten = (1...10).map { "Name \($0)" }
        #expect(try GarmentRules.otherNames(ten, name: "Top").count == 10)
        #expect(throws: FieldProblem.tooMany(maximum: 10)) {
            try GarmentRules.otherNames(ten + ["Name 11"], name: "Top")
        }
    }

    @Test func addingANameChecksItAgainstTheOthers() throws {
        var details = GarmentDetails(name: "Sage cardigan", otherNames: ["Cozy one"], category: .layer)
        #expect(try GarmentRules.newOtherName("  Green cardigan ", adding: details) == "Green cardigan")
        #expect(throws: FieldProblem.empty) { try GarmentRules.newOtherName("   ", adding: details) }
        #expect(throws: FieldProblem.duplicate) { try GarmentRules.newOtherName("cozy ONE", adding: details) }
        #expect(throws: FieldProblem.duplicate) { try GarmentRules.newOtherName("Sage Cardigan", adding: details) }
        details.otherNames = (1...10).map { "Name \($0)" }
        #expect(throws: FieldProblem.tooMany(maximum: 10)) {
            try GarmentRules.newOtherName("One more", adding: details)
        }
    }

    @Test func aProblemWithOtherNamesStopsSave() {
        let details = GarmentDetails(
            name: "Top", otherNames: [String(repeating: "a", count: 41)], category: .top)
        #expect(GarmentRules.problems(in: details)[.otherNames] == .tooLong(maximum: 40))
        #expect(GarmentRules.problems(in: details).fields == [.otherNames])
    }

    @Test func everyTypeBelongsToOneKind() {
        for category in GarmentCategory.allCases {
            #expect(GarmentSubKind.choices(for: category).allSatisfy { $0.category == category })
        }
        #expect(GarmentSubKind.choices(for: .layer) == [.cardigan, .jacket, .blazer, .coat, .vest])
        #expect(GarmentSubKind.choices(for: .dress).isEmpty)
        #expect(
            Set(GarmentCategory.allCases.flatMap(GarmentSubKind.choices(for:))) == Set(GarmentSubKind.allCases))
    }

    @Test func aTypeFromAnotherKindIsDropped() throws {
        let details = GarmentDetails(name: "Loafers", category: .shoes, subKind: .cardigan)
        #expect(try GarmentRules.checked(details).subKind == nil)
        var garment = Make.garment("g-1", .layer)
        GarmentDetails(name: "Loafers", category: .shoes, subKind: .loafers).apply(to: &garment)
        #expect(garment.category == .shoes && garment.subKind == .loafers)
        GarmentDetails(name: "Loafers", category: .top, subKind: .loafers).apply(to: &garment)
        #expect(garment.category == .top && garment.subKind == nil)
    }

    @Test func detailsCarryTheNewFieldsBothWays() throws {
        var garment = Make.garment("g-1", .layer)
        garment.otherNames = ["Cozy one"]
        garment.subKind = .cardigan
        let details = GarmentDetails(garment)
        #expect(details.otherNames == ["Cozy one"] && details.subKind == .cardigan)
        let made = try details.makeGarment(id: "g-2", addedAt: TestTime.now)
        #expect(made.otherNames == ["Cozy one"] && made.subKind == .cardigan)
    }

    @Test func theStoreKeepsOtherNamesTidy() throws {
        var garment = Make.garment("g-1", .top)
        garment.name = "Pink blouse"
        garment.otherNames = [" Bow top ", "bow top", "Pink blouse"]
        garment.subKind = .loafers
        let kept = try StoreValidation.garment(garment)
        #expect(kept.otherNames == ["Bow top"])
        #expect(kept.subKind == nil)
        garment.otherNames = (1...11).map { "Name \($0)" }
        #expect(throws: StoreError.self) { try StoreValidation.garment(garment) }
    }

    // MARK: Search

    @Test func closetSearchFindsOtherNames() {
        var blouse = Make.garment("g-blouse", .top, colors: [.pink])
        blouse.name = "Pink blouse"
        blouse.otherNames = ["Date-night top", "The bow one"]
        var tee = Make.garment("g-tee", .top)
        tee.name = "Striped tee"
        let garments = [blouse, tee]
        #expect(GarmentFilter(query: "date-night").apply(to: garments, suitcases: []).map(\.id) == ["g-blouse"])
        #expect(GarmentFilter(query: "bow pink").apply(to: garments, suitcases: []).map(\.id) == ["g-blouse"])
        #expect(GarmentFilter(query: "bow striped").apply(to: garments, suitcases: []).isEmpty)
    }

    @Test func savedLooksSearchFindsAPiecesOtherNamesAndType() {
        var blouse = Make.garment("g-blouse", .top, colors: [.pink])
        blouse.name = "Pink top"
        blouse.otherNames = ["Date-night top"]
        blouse.subKind = .blouse
        let look = Make.look("o-date", garments: ["g-blouse"])
        let garments = [blouse.id: blouse]
        let filter = LookFilter(query: "date-night")
        #expect(filter.apply(to: [look], garments: garments).count == 1)
        let pieces = LookFilter.pieces(of: look, garments: garments)
        #expect(pieces.first?.subKind == .blouse)
        // The screen adds the type's name as a piece word.
        let byType = LookFilter(query: "Blouse")
        #expect(byType.matches(name: nil, pieces: pieces, pieceWords: { [$0.subKind == .blouse ? "Blouse" : ""] }))
    }
}
