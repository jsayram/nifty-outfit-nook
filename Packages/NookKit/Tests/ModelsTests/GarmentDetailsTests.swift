import Foundation
import Models
import NookTestSupport
import Testing

/// What she types about a piece (Phase 7b): the checks, the defaults, and writing it to a
/// garment without touching its states.
struct GarmentRulesTests {
    private func details(name: String = "Sage cardigan", category: GarmentCategory? = .layer) -> GarmentDetails {
        GarmentDetails(name: name, category: category)
    }

    @Test func onlyANameAndAKindAreNeeded() throws {
        #expect(GarmentRules.problems(in: details()).isEmpty)
        let problems = GarmentRules.problems(in: details(name: "  ", category: nil))
        #expect(problems[.name] == .empty)
        #expect(problems[.category] == .missingChoice)
        // In form order, so the screen moves to the name first.
        #expect(problems.fields == [.name, .category])
    }

    @Test func everyProblemIsReportedAtOnce() {
        var details = details(name: String(repeating: "a", count: 61))
        details.brand = String(repeating: "b", count: 41)
        details.sizeLabel = "0\nPetite"
        details.colorNote = String(repeating: "c", count: 41)
        details.notes = String(repeating: "n", count: 2_001)
        let problems = GarmentRules.problems(in: details)
        #expect(problems[.name] == .tooLong(maximum: 60))
        #expect(problems[.brand] == .tooLong(maximum: 40))
        #expect(problems[.sizeLabel] == .controlCharacters)
        #expect(problems[.colorNote] == .tooLong(maximum: 40))
        #expect(problems[.notes] == .tooLong(maximum: 2_000))
        #expect(problems.fields == [.name, .colorNote, .brand, .sizeLabel, .notes])
    }

    @Test func limitsAreInclusive() {
        var details = details(name: String(repeating: "a", count: 60))
        details.brand = String(repeating: "b", count: 40)
        details.sizeLabel = String(repeating: "s", count: 20)
        details.notes = String(repeating: "n", count: 2_000)
        #expect(GarmentRules.problems(in: details).isEmpty)
    }

    @Test func checkingTrimsEveryTextField() throws {
        var details = details(name: "  Sage cardigan ")
        details.brand = " Old Navy  "
        details.colorNote = " Sage "
        details.notes = "\n Gold buttons.\nSoft.  \n"
        let checked = try GarmentRules.checked(details)
        #expect(checked.name == "Sage cardigan")
        #expect(checked.brand == "Old Navy")
        #expect(checked.colorNote == "Sage")
        // Notes keep their own line breaks inside.
        #expect(checked.notes == "Gold buttons.\nSoft.")
    }

    @Test func notesMayHaveSeveralLines() {
        var details = details()
        details.notes = "Bow at the neck.\nDry clean only."
        #expect(GarmentRules.problems(in: details).isEmpty)
    }

    @Test func aDescriptionHasALimit() throws {
        #expect(try GarmentRules.description("  sage cardigan \n") == "sage cardigan")
        #expect(throws: FieldProblem.tooLong(maximum: 1_000)) {
            try GarmentRules.description(String(repeating: "w", count: 1_001))
        }
    }

    @Test func storedGarmentsAreCheckedTheSameWay() {
        var garment = Make.garment("g-1", .top)
        #expect(GarmentRules.problems(in: garment).isEmpty)
        garment.brand = String(repeating: "b", count: 41)
        #expect(GarmentRules.problems(in: garment)[.brand] == .tooLong(maximum: 40))
    }
}

struct GarmentDetailsTests {
    @Test func blankHasTheGarmentDefaults() {
        let blank = GarmentDetails.blank
        let garment = Garment(id: "g-1", name: "x", category: .top, addedAt: TestTime.now)
        #expect(blank.name.isEmpty)
        #expect(blank.category == nil)
        #expect(blank.dressiness == garment.dressiness)
        #expect(blank.warmth == garment.warmth)
        #expect(blank.seasons == garment.seasons)
        #expect(blank.seasons.count == 4)
        #expect(blank.occasions.isEmpty)
        #expect(blank.fit == nil)
        #expect(blank.photo == .noPhoto)
    }

    @Test func makesAnOwnedCleanPiece() throws {
        var details = GarmentDetails(name: " Sage cardigan ", category: .layer, colors: [.green], colorNote: "Sage")
        details.brand = ""
        let garment = try details.makeGarment(id: "g-new", addedAt: TestTime.now)
        #expect(garment.id == "g-new")
        #expect(garment.name == "Sage cardigan")
        #expect(garment.category == .layer)
        #expect(garment.colors == [.green])
        #expect(garment.colorNote == "Sage")
        // Empty optional text is stored as unknown.
        #expect(garment.brand == nil)
        #expect(garment.sizeLabel == nil)
        #expect(garment.ownership == .owned)
        #expect(garment.laundry == .clean)
        #expect(garment.availability == .available)
        #expect(garment.wornOn.isEmpty)
        #expect(garment.addedAt == TestTime.now)
        #expect(garment.isInCloset)
    }

    @Test func aPieceWithoutANameOrKindIsNeverMade() {
        #expect(throws: GarmentProblems([.name: .empty, .category: .missingChoice])) {
            try GarmentDetails.blank.makeGarment(id: "g-new", addedAt: TestTime.now)
        }
    }

    @Test func roundTripsThroughAGarment() {
        var garment = Make.garment("g-1", .bottom, colors: [.navy, .white])
        garment.colorNote = "Ink"
        garment.fit = .relaxed
        garment.brand = "Demo"
        garment.sizeLabel = "0 Petite"
        garment.notes = "Ankle length"
        var copy = garment
        GarmentDetails(garment).apply(to: &copy)
        #expect(copy == garment)
    }

    @Test func applyingLeavesTheStatesAlone() {
        var garment = Make.garment("g-1", .top, ownership: .purchased(.notArrived), laundry: .dirty)
        garment.wornOn = [TestTime.day(-3)]
        garment.availability = .unavailable(until: nil)
        var details = GarmentDetails(garment)
        details.name = "Renamed"
        details.category = .layer
        details.apply(to: &garment)
        #expect(garment.name == "Renamed")
        #expect(garment.category == .layer)
        #expect(garment.ownership == .purchased(.notArrived))
        #expect(garment.laundry == .dirty)
        #expect(garment.wornOn == [TestTime.day(-3)])
        #expect(garment.availability == .unavailable(until: nil))
    }
}

struct GarmentSuggestionTests {
    @Test func eachSuggestionFillsItsField() {
        var details = GarmentDetails.blank
        let suggestions: [GarmentSuggestion] = [
            .name("Sage cardigan"), .category(.layer), .colors([.green], note: "Sage"), .fit(.relaxed),
            .dressiness(.casual), .warmth(.warm), .seasons([.fall, .winter]), .occasions([.casual]),
            .brand("Old Navy"), .detail("Gold buttons"),
        ]
        for suggestion in suggestions { suggestion.apply(to: &details) }
        #expect(details.name == "Sage cardigan")
        #expect(details.category == .layer)
        #expect(details.colors == [.green])
        #expect(details.colorNote == "Sage")
        #expect(details.fit == .relaxed)
        #expect(details.dressiness == .casual)
        #expect(details.warmth == .warm)
        #expect(details.seasons == [.fall, .winter])
        #expect(details.occasions == [.casual])
        #expect(details.brand == "Old Navy")
        #expect(details.notes == "Gold buttons")
    }

    @Test func aDetailIsAddedToHerNotesOnce() {
        var details = GarmentDetails(notes: "Soft.")
        GarmentSuggestion.detail("Gold buttons").apply(to: &details)
        GarmentSuggestion.detail("gold buttons").apply(to: &details)
        #expect(details.notes == "Soft.\nGold buttons")
    }

    @Test func coloursWithoutAShadeKeepHerShade() {
        var details = GarmentDetails(colorNote: "Ink")
        GarmentSuggestion.colors([.navy], note: nil).apply(to: &details)
        #expect(details.colors == [.navy])
        #expect(details.colorNote == "Ink")
    }
}

struct GarmentDraftTests {
    @Test func aDraftCountsOnlyWithChanges() {
        let blank = GarmentDraft(
            target: .newPiece, step: .choose, details: .blank, base: .blank, savedAt: TestTime.now)
        #expect(!blank.hasChanges)
        var words = blank
        words.description = "  "
        #expect(!words.hasChanges)
        words.description = "navy trousers"
        #expect(words.hasChanges)
        var named = blank
        named.details.name = "Navy trousers"
        #expect(named.hasChanges)
    }

    @Test func anEditCountsOnlyWhenItDiffersFromThePiece() {
        let base = GarmentDetails(Make.garment("g-1", .top))
        var draft = GarmentDraft(
            target: .garment("g-1"), step: .details, details: base, base: base, savedAt: TestTime.now)
        #expect(!draft.hasChanges)
        draft.details.warmth = .warm
        #expect(draft.hasChanges)
    }

    @Test func draftsEncodeAndDecode() throws {
        let draft = GarmentDraft(
            target: .garment("g-1"), step: .details,
            details: GarmentDetails(name: "A", category: .top, notes: "Private"), base: .blank,
            description: "words", savedAt: TestTime.now)
        let data = try JSONEncoder().encode(draft)
        #expect(try JSONDecoder().decode(GarmentDraft.self, from: data) == draft)
    }
}
