import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Closet's Possible matches (PRD §7.6): only when nothing has every word, never in a picker, and
/// each piece says which words it doesn't have.
@MainActor
struct ClosetPossibleMatchesTests {
    private func search(_ model: ClosetModel, _ text: String) {
        model.searchText = text
        model.applySearchNow()
    }

    @Test func nothingHasEveryWordSoPossibleMatchesShow() async {
        let model = await loadedClosetModel(.demo)
        search(model, "my navy party pants")
        #expect(model.shown.isEmpty)
        #expect(model.hasNoMatches)
        #expect(model.possible.first?.id == "g-navy-trousers")
        #expect(model.possible.first?.note == "2 of 3 words")
        #expect(model.possible.first?.spokenNote == "Has “navy” and “pants”. Not recorded: “party”")
        #expect(model.missingEverywhere == ["party"])
        #expect(model.possibleMatchesNote.hasSuffix("None of them has “party”."))
        #expect(model.possible.contains { $0.id == "g-navy-cardigan" })
        #expect(model.possible.count <= GarmentFilter.possibleMatchesMaximum)
        // Filler words are left out of what Remember this name offers.
        #expect(model.rememberSuggestion == "navy party pants")
    }

    @Test func realResultsMeanNoPossibleMatches() async {
        let model = await loadedClosetModel(.demo)
        search(model, "navy pants")
        #expect(model.shown.map(\.id) == ["g-navy-trousers"])
        #expect(model.possible.isEmpty)
        #expect(model.rememberSuggestion == nil)
    }

    @Test func chipsStillApply() async {
        let model = await loadedClosetModel(.demo)
        model.toggle(.layer)
        search(model, "navy party pants")
        #expect(model.possible.map(\.id) == ["g-navy-cardigan"])
    }

    @Test func clearingTakesThemAway() async {
        let model = await loadedClosetModel(.demo)
        search(model, "navy party pants")
        #expect(!model.possible.isEmpty)
        model.clearFilters()
        #expect(model.possible.isEmpty)
        #expect(model.shown.count == model.items.count)
    }

    @Test func aPickerDoesntShowThem() async {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let model = ClosetModel(scope: PieceScope(garmentIDs: ["g-navy-trousers", "g-navy-cardigan"]))
        await model.load(from: services, now: TestTime.now)
        search(model, "navy party pants")
        #expect(model.shown.isEmpty)
        #expect(model.possible.isEmpty)
    }
}
