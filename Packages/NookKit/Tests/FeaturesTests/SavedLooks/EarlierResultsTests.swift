import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// LR-06.4 (Phase 21c): an earlier result she didn't save is findable in Saved Looks' search but
/// never listed with her saved looks, and opens on look detail with Save look. The demo closet
/// has one, "o-history-casual" (cream sweater, wide jeans, white sneakers).
@MainActor
struct EarlierResultsTests {
    private let us = TestTime.locale

    private func search(_ model: SavedLooksModel, _ text: String) {
        model.searchText = text
        model.applySearchNow()
    }

    @Test func onlyTypedSearchFindsThem() async {
        let model = await loadedSavedLooks(searchDelay: .zero)
        #expect(model.earlierItems.map(\.id) == ["o-history-casual"])
        // Never on the list of saved looks, and not shown without typed words.
        #expect(!model.items.contains { $0.id == "o-history-casual" })
        #expect(model.shownEarlier.isEmpty)
        model.toggle(.bottom)
        #expect(model.shownEarlier.isEmpty)
        model.clearFilters()

        search(model, "sweater")
        #expect(model.shownEarlier.map(\.id) == ["o-history-casual"])
        #expect(!model.shown.contains { $0.id == "o-history-casual" })
        // The chips narrow them as they narrow saved looks.
        model.toggle(.dress)
        #expect(model.shownEarlier.isEmpty)
        model.toggle(.dress)
        model.toggle(.bottom)
        #expect(model.shownEarlier.map(\.id) == ["o-history-casual"])

        search(model, "")
        #expect(model.shownEarlier.isEmpty)
        #expect(model.isEarlierResult("o-history-casual"))
        #expect(!model.isEarlierResult("o-interview"))
    }

    /// A search that only an earlier result matches isn't "no matches".
    @Test func anEarlierResultCountsAsAMatch() async throws {
        let model = await loadedSavedLooks(searchDelay: .zero)
        let words = try #require(model.earlierItems.first).look.garmentIDs.map(\.rawValue)
        #expect(words.contains("g-cream-sweater"))
        search(model, "zzz-nothing")
        #expect(model.hasNoMatches)
        // A word only the earlier result has: the sweater's own name.
        let sweaterOnly = !model.items.contains { item in item.matches(LookFilter(query: "cream sweater")) }
        search(model, "cream sweater")
        if sweaterOnly { #expect(model.shown.isEmpty) }
        #expect(!model.hasNoMatches)
    }

    @Test func itOpensOnLookDetailWithSaveLook() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        // Opened any other way it's missing, as before.
        let plain = LookDetailModel(lookID: "o-history-casual", now: { TestTime.now }, calendar: TestTime.calendar)
        await plain.load(from: services)
        #expect(plain.phase == .missing)

        let model = LookDetailModel(
            lookID: "o-history-casual", allowsEarlierResult: true, now: { TestTime.now }, calendar: TestTime.calendar)
        await model.load(from: services)
        #expect(model.phase == .loaded)
        #expect(model.isEarlierResult)
        #expect(model.facts(locale: us) == ["Casual", "Simple", "Made Oct 11", "Not saved"])

        let before = try await model.saveEarlierResult(locale: us)
        #expect(!before.isSaved)
        #expect(!model.isEarlierResult)
        let saved = try #require(try await services.looks.looks().first { $0.id == "o-history-casual" })
        #expect(saved.isSaved && saved.savedAt == TestTime.now)
        #expect(saved.name?.isEmpty == false)
        #expect(model.facts(locale: us).contains("Saved today"))

        // Undo puts it back as an earlier result.
        try await model.restore(before)
        #expect(try await services.looks.looks().first { $0.id == "o-history-casual" } == before)
    }
}
