import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Saved Looks' scope switch (Phase 21c, decided 21 October 2026): Saved lists her saved looks, All
/// lists those plus every Style Me result she kept but didn't save (LR-06.4), in one list. Search
/// and the chips work the same in both, and on Saved a line says how many more All has for the
/// same search and chips. This replaces 21c's "Earlier results" group, which only typed search
/// brought up.
///
/// The demo closet has nine saved looks and one unsaved result, `o-history-casual` (cream sweater,
/// wide jeans, white sneakers). Where a test needs more, `savedLooks(unsaving:)` turns saved ones
/// into unsaved results. Newest made first, the demo's looks run: history, brunch idea, weekend,
/// interview, lace date, office lace, casual jeans, date crop, weekend olive, blazer office.
@MainActor
struct SavedLooksScopeTests {
    private let us = TestTime.locale

    private func ids(_ model: SavedLooksModel) -> [String] {
        model.shown.map(\.id.rawValue)
    }

    private func search(_ model: SavedLooksModel, _ text: String) {
        model.searchText = text
        model.applySearchNow()
    }

    // MARK: The two lists

    @Test func startsOnSavedWithOnlySavedLooks() async {
        let model = await loadedSavedLooks()
        #expect(model.scope == .saved)
        #expect(model.shown.count == 9)
        #expect(!ids(model).contains("o-history-casual"))
        #expect(model.headerCountText == "9 looks")
        #expect(model.countText == "9 looks")
        // Nothing typed or chosen: no nudge, though one unsaved result exists.
        #expect(model.hasUnsaved)
        #expect(model.moreInAll == 0)
    }

    /// One list, no separate group: saved and unsaved together, newest made first.
    @Test func allListsEveryLookInOneList() async {
        let model = await loadedSavedLooks()
        model.scope = .all
        #expect(
            ids(model) == [
                "o-history-casual", "o-brunch-idea", "o-weekend", "o-interview", "o-lace-date", "o-office-lace",
                "o-casual-jeans", "o-date-crop", "o-weekend-olive", "o-blazer-office",
            ])
        #expect(model.headerCountText == "10 looks, 1 not saved")
        #expect(model.countText == "10 looks")
        #expect(model.shown.filter { !$0.isSaved }.map(\.id.rawValue) == ["o-history-casual"])
        #expect(model.moreInAll == 0)
        // Back on Saved nothing is left over.
        model.scope = .saved
        #expect(model.shown.count == 9)
    }

    /// With nothing unsaved, All is Saved, and the count has nothing to add.
    @Test func allWithNothingUnsavedIsTheSameList() async {
        let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        var looks = data.looks
        for index in looks.indices where !looks[index].isSaved {
            looks[index].isSaved = true
            looks[index].savedAt = looks[index].createdAt
        }
        let model = SavedLooksModel(searchDelay: .zero)
        model.show(looks, garments: data.garments, now: TestTime.now)
        #expect(!model.hasUnsaved)
        let saved = ids(model)
        model.scope = .all
        #expect(model.headerCountText == "10 looks")
        #expect(Set(ids(model)) == Set(saved))
        #expect(model.shown.allSatisfy { $0.isSaved })
    }

    // MARK: Search and filters are the same in both scopes

    /// Search and the chips on both scopes, with three unsaved looks (history, weekend olive, lace
    /// date). Words are matched against the whole look and a chip with a swatch against one piece,
    /// the same on both. Saved's list is newest saved first, All's newest made first.
    @Test func searchAndFiltersApplyTheSameWayInBothScopes() async {
        let model = savedLooks(unsaving: ["o-weekend-olive", "o-lace-date"])
        let unsaved: Set<String> = ["o-history-casual", "o-weekend-olive", "o-lace-date"]
        typealias Case = (words: String, kinds: [GarmentCategory], colors: [ColorName], saved: [String], all: [String])
        let everySaved = [
            "o-brunch-idea", "o-weekend", "o-interview", "o-office-lace", "o-casual-jeans", "o-date-crop",
            "o-blazer-office",
        ]
        let every = [
            "o-history-casual", "o-brunch-idea", "o-weekend", "o-interview", "o-lace-date", "o-office-lace",
            "o-casual-jeans", "o-date-crop", "o-weekend-olive", "o-blazer-office",
        ]
        let cases: [Case] = [
            ("", [], [], everySaved, every),
            ("denim", [], [], ["o-casual-jeans"], ["o-history-casual", "o-casual-jeans"]),
            ("denim", [.bottom], [], ["o-casual-jeans"], ["o-history-casual", "o-casual-jeans"]),
            // The words look at the whole look; a chip needs one piece of that kind. Both looks have a top.
            ("denim", [.top], [], ["o-casual-jeans"], ["o-history-casual", "o-casual-jeans"]),
            ("denim", [.dress], [], [], []),
            ("olive", [], [], ["o-brunch-idea", "o-weekend"], ["o-brunch-idea", "o-weekend", "o-weekend-olive"]),
            ("loafers", [], [], ["o-brunch-idea"], ["o-brunch-idea", "o-weekend-olive"]),
            ("sweater", [], [], ["o-blazer-office"], ["o-history-casual", "o-weekend-olive", "o-blazer-office"]),
            ("", [.bag], [], ["o-casual-jeans"], ["o-lace-date", "o-casual-jeans"]),
            ("", [], [.denim], ["o-casual-jeans"], ["o-history-casual", "o-casual-jeans"]),
            // A chip and a swatch are one piece: black bottoms, not a bottom and something black.
            ("", [.bottom], [.black], ["o-date-crop"], ["o-lace-date", "o-date-crop"]),
            ("", [.bottom], [.cream], [], []),
            (
                "", [.top], [.cream], ["o-date-crop", "o-blazer-office"],
                [
                    "o-history-casual", "o-date-crop", "o-weekend-olive", "o-blazer-office",
                ]
            ),
            ("date night", [], [], ["o-date-crop"], ["o-lace-date", "o-date-crop"]),
            ("zzz", [], [], [], []),
        ]
        for item in cases {
            model.clearFilters()
            search(model, item.words)
            for kind in item.kinds { model.toggle(kind) }
            for color in item.colors { model.toggle(color) }
            let what = "\(item.words) \(item.kinds.map(\.rawValue)) \(item.colors.map(\.rawValue))"

            model.scope = .saved
            #expect(ids(model) == item.saved, "Saved: \(what)")
            let nudge = model.moreInAll
            model.scope = .all
            #expect(ids(model) == item.all, "All: \(what)")
            // No special cases: All is the saved matches plus the unsaved ones, nothing else.
            #expect(Set(item.all).subtracting(unsaved) == Set(item.saved), "\(what)")
            #expect(nudge == (model.filter.isActive ? item.all.filter(unsaved.contains).count : 0), "Nudge: \(what)")
        }
    }

    @Test func switchingScopeKeepsTheSearchAndFilters() async {
        let model = await loadedSavedLooks()
        search(model, "denim")
        model.toggle(.bottom)
        model.toggle(.denim)
        model.scope = .all
        #expect(model.searchText == "denim")
        #expect(model.filter == LookFilter(categories: [.bottom], colors: [.denim], query: "denim"))
        model.scope = .saved
        #expect(model.filter == LookFilter(categories: [.bottom], colors: [.denim], query: "denim"))
        // Clear leaves the scope alone.
        model.scope = .all
        model.clearFilters()
        #expect(model.scope == .all)
        #expect(!model.filter.isActive)
    }

    // MARK: The nudge

    /// "N more in All" counts the unsaved looks the current search and chips match.
    @Test func theNudgeCountsTheUnsavedLooksTheSearchMatches() async {
        let model = savedLooks(unsaving: ["o-weekend-olive", "o-lace-date"])
        search(model, "denim")
        #expect(model.moreInAll == 1)
        search(model, "sweater")
        #expect(model.moreInAll == 2)
        search(model, "navy")
        #expect(model.moreInAll == 0)
        // Chips alone count too, and so do swatches.
        model.clearFilters()
        model.toggle(.bag)
        #expect(ids(model) == ["o-casual-jeans"])
        #expect(model.moreInAll == 1)
        model.toggle(.bag)
        model.toggle(.cream)
        #expect(model.moreInAll == 2)
        // Words and chips narrow it together.
        search(model, "loafers")
        #expect(model.moreInAll == 1)
        search(model, "zzz")
        #expect(model.moreInAll == 0)
    }

    /// With nothing typed or chosen every unsaved look "matches", so the line stays away.
    @Test func noNudgeWithoutASearchOrFilter() async {
        let model = savedLooks(unsaving: ["o-weekend-olive", "o-lace-date"])
        #expect(model.hasUnsaved)
        #expect(model.moreInAll == 0)
        search(model, "   ")
        #expect(model.moreInAll == 0)
        search(model, "denim")
        #expect(model.moreInAll == 1)
        search(model, "")
        #expect(model.moreInAll == 0)
    }

    @Test func noNudgeOnAll() async {
        let model = savedLooks(unsaving: ["o-weekend-olive", "o-lace-date"])
        search(model, "sweater")
        #expect(model.moreInAll == 2)
        model.scope = .all
        #expect(model.moreInAll == 0)
        model.scope = .saved
        #expect(model.moreInAll == 2)
    }

    /// Tapping the line is `scope = .all`: the same search and chips, now with the unsaved matches.
    @Test func theNudgeCountIsWhatAllAddsToSaved() async {
        let model = savedLooks(unsaving: ["o-weekend-olive", "o-lace-date"])
        for (words, kind) in [("sweater", GarmentCategory?.none), ("", .bottom), ("denim", .bottom), ("a", nil)] {
            model.clearFilters()
            model.scope = .saved
            search(model, words)
            if let kind { model.toggle(kind) }
            let before = model.shown.count
            let more = model.moreInAll
            model.scope = .all
            #expect(model.shown.count == before + more, "\(words) \(String(describing: kind))")
        }
    }

    @Test func theNudgeSaysMoreInAll() {
        #expect(SavedLooksText.moreInAll(1) == "1 more in All")
        #expect(SavedLooksText.moreInAll(2) == "2 more in All")
        #expect(SavedLooksText.moreInAll(12) == "12 more in All")
    }

    // MARK: Empty states

    @Test func emptyStatesNameTheirScope() async {
        // No looks at all.
        let none = await loadedSavedLooks(.empty)
        #expect(none.isEmpty && !none.hasUnsaved)
        none.scope = .all
        #expect(none.isEmpty)
        #expect(none.headerCountText == "")
        #expect(SavedLooksText.emptyTitle == "Nothing saved yet")
        #expect(SavedLooksText.emptyAllTitle == "No looks yet")

        // Only unsaved results: Saved is empty and says so, All lists them.
        let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        var looks = data.looks
        for index in looks.indices {
            looks[index].isSaved = false
            looks[index].savedAt = nil
        }
        let unsavedOnly = SavedLooksModel(searchDelay: .zero)
        unsavedOnly.show(looks, garments: data.garments, now: TestTime.now)
        #expect(unsavedOnly.isEmpty && unsavedOnly.hasUnsaved)
        unsavedOnly.scope = .all
        #expect(!unsavedOnly.isEmpty)
        #expect(unsavedOnly.shown.count == 10)
        #expect(unsavedOnly.headerCountText == "10 looks, 10 not saved")
    }

    @Test func noMatchesNameTheirScopeWithAndWithoutSearch() async {
        let model = savedLooks(unsaving: ["o-casual-jeans", "o-lace-date"])
        // Saved: a chip alone, then a search; the filters in words, and the nudge.
        model.toggle(.bag)
        #expect(model.hasNoMatches && !model.isEmpty)
        #expect(model.filterSummary == "Bags")
        #expect(model.moreInAll == 2)
        search(model, "burgundy")
        #expect(model.hasNoMatches)
        #expect(model.filterSummary == "Bags · “burgundy”")
        #expect(model.moreInAll == 2)
        // All has them.
        model.scope = .all
        #expect(!model.hasNoMatches)
        #expect(ids(model) == ["o-lace-date", "o-casual-jeans"])
        // Nothing anywhere.
        search(model, "zzz")
        #expect(model.hasNoMatches)
        #expect(model.moreInAll == 0)
        #expect(SavedLooksText.noMatchesTitle == "No saved looks match")
        #expect(SavedLooksText.noMatchesAllTitle == "No looks match in All")
        // Clear brings back the scope's own list.
        model.clearFilters()
        #expect(model.shown.count == 10)
    }

    // MARK: Swatches follow the scope

    /// Both burgundy bags are in unsaved looks here, so the swatch is on All and not on Saved.
    @Test func aSwatchOnlyUnsavedLooksHaveShowsOnAll() async {
        let model = savedLooks(unsaving: ["o-lace-date", "o-casual-jeans"])
        #expect(!model.colorChoices.contains(.burgundy))
        model.scope = .all
        #expect(model.colorChoices.contains(.burgundy))
        // The Pictures tab is about saved looks, whatever the scope.
        model.tab = .pictures
        #expect(!model.colorChoices.contains(.burgundy))
        model.tab = .looks
        #expect(model.colorChoices.contains(.burgundy))
    }

    /// A swatch she turned on stays on show when she goes back to Saved, so she can turn it off, and
    /// Saved then says nothing matches and where the looks are.
    @Test func aSwatchSheTurnedOnIsNeverDropped() async {
        let model = savedLooks(unsaving: ["o-lace-date", "o-casual-jeans"])
        model.scope = .all
        model.toggle(.burgundy)
        #expect(ids(model) == ["o-lace-date", "o-casual-jeans"])
        model.scope = .saved
        #expect(model.filter.colors == [.burgundy])
        #expect(model.colorChoices.contains(.burgundy))
        #expect(model.hasNoMatches)
        #expect(model.moreInAll == 2)
        model.toggle(.burgundy)
        #expect(!model.colorChoices.contains(.burgundy))
        #expect(model.shown.count == 7)
    }

    // MARK: Save look, from the grid

    /// Saving a look on All changes it where it is: same place in the list, no tag, named.
    @Test func saveLookChangesTheLookInPlace() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let model = await loadedSavedLooksFrom(services, searchDelay: .zero)
        model.scope = .all
        search(model, "denim")
        #expect(ids(model) == ["o-history-casual", "o-casual-jeans"])
        let tagged = try #require(model.shown.first)
        #expect(!tagged.isSaved)

        let before = try #require(
            try await model.save("o-history-casual", locale: us, using: services, now: TestTime.now))
        #expect(!before.isSaved)
        #expect(ids(model) == ["o-history-casual", "o-casual-jeans"])
        let item = try #require(model.shown.first)
        #expect(item.isSaved && item.look.savedAt == TestTime.now)
        #expect(!item.name.isEmpty)
        #expect(!model.isNotSaved("o-history-casual"))
        #expect(!model.hasUnsaved)
        #expect(model.headerCountText == "10 looks")

        // It's in the store, and on Saved, first, since it was saved last.
        let stored = try await services.looks.look("o-history-casual")
        #expect(stored.isSaved && stored.name == item.name)
        model.scope = .saved
        #expect(ids(model) == ["o-history-casual", "o-casual-jeans"])
        #expect(model.moreInAll == 0)
        search(model, "")
        #expect(ids(model).first == "o-history-casual")
        #expect(model.headerCountText == "10 looks")
    }

    /// A second tap while it saves, or on a look that is saved, does nothing.
    @Test func saveLookTwiceSavesOnce() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let model = await loadedSavedLooksFrom(services, searchDelay: .zero)
        #expect(try await model.save("o-history-casual", locale: us, using: services, now: TestTime.now) != nil)
        #expect(try await model.save("o-history-casual", locale: us, using: services, now: TestTime.now) == nil)
        #expect(try await model.save("o-interview", locale: us, using: services, now: TestTime.now) == nil)
        #expect(try await model.save("o-missing", locale: us, using: services, now: TestTime.now) == nil)
    }

    /// Undo puts the exact look back, unsaved and where it was.
    @Test func undoSaveLookPutsItBack() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let model = await loadedSavedLooksFrom(services, searchDelay: .zero)
        model.scope = .all
        let order = ids(model)
        let before = try #require(
            try await model.save("o-history-casual", locale: us, using: services, now: TestTime.now))
        try await model.undoSave(before, using: services)
        #expect(ids(model) == order)
        #expect(model.isNotSaved("o-history-casual"))
        #expect(try await services.looks.look("o-history-casual") == before)
        model.scope = .saved
        #expect(model.shown.count == 9)
    }

    // MARK: Words

    @Test func anUnsavedLookSaysSoToVoiceOver() async throws {
        let model = await loadedSavedLooks()
        let unsaved = try #require(model.item("o-history-casual"))
        let spoken = SavedLooksText.spokenDetail(of: unsaved, lastWorn: nil, made: "Made Oct 11")
        #expect(spoken == "Casual, Made Oct 11, Not saved")
        let saved = try #require(model.item("o-interview"))
        #expect(
            SavedLooksText.spokenDetail(of: saved, lastWorn: "Last worn 5 days ago", made: "Made Oct 11")
                == "Office, Last worn 5 days ago")
        #expect(SavedLooksText.saveLookSpoken("Casual look") == "Save look: Casual look")
        #expect(SavedLooksText.notSaved == "Not saved")
    }

    // MARK: Look detail (LR-06.4)

    /// An unsaved look opens on look detail from All, with its facts and Save look; opened any
    /// other way it's still missing.
    @Test func itOpensOnLookDetailWithSaveLook() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
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

        // Undo puts it back as an unsaved result.
        try await model.restore(before)
        #expect(try await services.looks.looks().first { $0.id == "o-history-casual" } == before)
    }
}
