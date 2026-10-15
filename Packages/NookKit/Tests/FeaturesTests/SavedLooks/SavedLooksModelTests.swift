import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// A Saved Looks model loaded from a fixture set, the way the screen loads it.
@MainActor
func loadedSavedLooks(
    _ set: FixtureSet = .demo, behavior: FixtureBehavior = .normal, searchDelay: Duration = .milliseconds(250)
) async -> SavedLooksModel {
    let services = FixtureServices.make(
        set: set, behavior: behavior, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
    let model = SavedLooksModel(searchDelay: searchDelay)
    await model.load(from: services, now: ClosetTestTime.now)
    return model
}

/// Saved Looks (Phase 12a, RD-08, LR-09) on the demo closet: five saved looks and one unsaved
/// result kept as history.
@MainActor
struct SavedLooksModelTests {
    private func ids(_ model: SavedLooksModel) -> [String] {
        model.shown.map(\.id.rawValue)
    }

    // MARK: Loading

    /// RD-08: every saved look, newest saved first. Unsaved results stay out (LR-06.4).
    @Test func showsSavedLooksNewestFirst() async {
        let model = await loadedSavedLooks()
        #expect(model.phase == .loaded)
        #expect(ids(model) == ["o-brunch-idea", "o-weekend", "o-interview", "o-lace-date", "o-blazer-office"])
        #expect(model.countText == "5 looks")
        #expect(!model.isEmpty)
    }

    /// A look saved today goes first, even though its result was made earlier.
    @Test func orderFollowsWhenSaved() async {
        let model = SavedLooksModel()
        let data = FixtureSet.demo.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        var looks = data.looks
        if let index = looks.firstIndex(where: { $0.id == "o-blazer-office" }) {
            looks[index].savedAt = ClosetTestTime.now
        }
        model.show(looks, garments: data.garments, now: ClosetTestTime.now)
        #expect(ids(model).first == "o-blazer-office")
    }

    /// RD-08.4: nothing saved yet.
    @Test func emptySet() async {
        let model = await loadedSavedLooks(.empty)
        #expect(model.isEmpty)
        #expect(model.countText == "")
        #expect(!model.hasNoMatches)
    }

    @Test func failingStoresShowTheErrorState() async {
        let model = await loadedSavedLooks(behavior: .storesFail)
        #expect(model.phase == .failed)
    }

    /// The names and the occasion line, worked out once per look.
    @Test func itemsCarryTheirWords() async throws {
        let model = await loadedSavedLooks()
        let lace = try #require(model.item("o-lace-date"))
        #expect(lace.name == "Lace date night")
        #expect(lace.occasion == "Date night")
        #expect(lace.content.pieces.count == 4)
    }

    // MARK: Search

    /// RD-08.3: search finds a look by its name, a piece's name, or its occasion.
    @Test func searchFindsNamesPiecesAndOccasions() async {
        let model = await loadedSavedLooks(searchDelay: .zero)
        for (query, expected) in [
            ("interview", ["o-interview"]),
            ("loafers", ["o-brunch-idea"]),
            ("date night", ["o-lace-date"]),
            ("cardigan", ["o-brunch-idea", "o-interview"]),
            ("shoes", ["o-brunch-idea", "o-weekend", "o-interview", "o-lace-date", "o-blazer-office"]),
            ("navy heels", ["o-blazer-office"]),
        ] {
            model.searchText = query
            await model.settleSearch()
            #expect(ids(model) == expected, "\(query)")
        }
    }

    /// Typing waits for a pause, so a long list isn't filtered on every letter.
    @Test func typedSearchWaitsForAPause() async {
        let model = await loadedSavedLooks(searchDelay: .milliseconds(50))
        for text in ["l", "la", "lac", "lace"] { model.searchText = text }
        #expect(model.searchesApplied == 0)
        await model.settleSearch()
        #expect(model.searchesApplied == 1)
        #expect(ids(model) == ["o-lace-date"])
        // Emptying the field shows everything at once.
        model.searchText = ""
        #expect(model.shown.count == 5)
    }

    // MARK: Filters

    /// LR-09.1: chips and swatches alone, together and with text, and Clear (LR-09.3).
    @Test func chipsAndSwatchesFilter() async {
        let model = await loadedSavedLooks(searchDelay: .zero)
        model.toggle(.bag)
        #expect(ids(model) == ["o-lace-date"])
        model.toggle(.bag)
        model.toggle(.bottom)
        model.toggle(.black)
        // Black bottoms: only the lace look's skirt.
        #expect(ids(model) == ["o-lace-date"])
        #expect(model.countText == "1 of 5 looks")
        #expect(model.filterSummary == "Bottoms · Black")
        model.toggle(.black)
        model.toggle(.olive)
        #expect(ids(model) == ["o-brunch-idea", "o-weekend"])
        model.searchText = "brick"
        await model.settleSearch()
        #expect(ids(model) == ["o-weekend"])
        #expect(model.filterSummary == "Bottoms · Olive · “brick”")
        model.clearFilters()
        #expect(model.shown.count == 5)
        #expect(!model.filter.isActive)
        #expect(model.searchText == "")
    }

    /// LR-09.3: no match names the filters; Clear filters brings everything back.
    @Test func noMatches() async {
        let model = await loadedSavedLooks()
        model.toggle(.dress)
        #expect(model.hasNoMatches)
        #expect(model.filterSummary == "Dresses")
        model.clearFilters()
        #expect(!model.hasNoMatches)
    }

    /// The chips: LR-09's six; the swatches: only colours in her saved looks.
    @Test func choicesFollowHerLooks() async {
        let model = await loadedSavedLooks()
        #expect(model.pieceKinds == [.top, .bottom, .dress, .layer, .shoes, .bag])
        #expect(model.colorChoices.contains(.navy))
        #expect(model.colorChoices.contains(.cream))  // the idea's colour
        #expect(!model.colorChoices.contains(.blue))  // only the blue dress, in no saved look
    }

    // MARK: Pieces that left her closet

    /// LR-16.4: the gray blazer she gave away, and the archived skirt, show as removed.
    @Test func removedPiecesAreCounted() async throws {
        let model = await loadedSavedLooks()
        #expect(try #require(model.item("o-blazer-office")).removedCount == 1)
        #expect(try #require(model.item("o-lace-date")).removedCount == 1)
        #expect(try #require(model.item("o-interview")).removedCount == 0)
        let blazer = try #require(model.item("o-blazer-office")?.content.removed.first)
        #expect(blazer.name == "Gray blazer")
        #expect(blazer.removal == .noLongerOwned)
        #expect(
            LookBundleText.spokenName(of: blazer) == "Gray blazer (No longer in your closet)")
    }

    // MARK: Delete and Undo

    /// Delete look from its detail, then Undo from the line over the looks.
    @Test func undoBringsADeletedLookBack() async throws {
        let services = FixtureServices.make(set: .demo, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        let model = SavedLooksModel()
        await model.load(from: services, now: ClosetTestTime.now)
        let detail = LookDetailModel(
            lookID: "o-weekend", now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar)
        await detail.load(from: services)
        model.lastRemoval = try await detail.delete()
        await model.load(from: services, now: ClosetTestTime.now)
        #expect(!ids(model).contains("o-weekend"))
        #expect(model.lastRemoval?.name == "Weekend olive and brick")

        await model.undoLastRemoval(using: services, now: ClosetTestTime.now)
        #expect(model.lastRemoval == nil)
        #expect(ids(model) == ["o-brunch-idea", "o-weekend", "o-interview", "o-lace-date", "o-blazer-office"])
    }

    // MARK: Large set

    /// The large set's 480-odd saved looks load, search and filter without a stall.
    @Test func largeSetStaysQuick() async {
        let data = FixtureSet.large.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        let model = SavedLooksModel(searchDelay: .zero)
        let loading = SpeedCheck.fastest {
            model.show(data.looks, garments: data.garments, now: ClosetTestTime.now)
        }
        #expect(model.items.count > 400)
        #expect(loading < SpeedCheck.limit(.milliseconds(500)), "Loading took \(loading)")
        let filtering = SpeedCheck.fastest {
            model.toggle(.bottom)
            model.toggle(.black)
            model.applySearchNow()
            model.clearFilters()
        }
        #expect(filtering < SpeedCheck.limit(.milliseconds(250)), "Filtering took \(filtering)")
        model.searchText = "office"
        model.applySearchNow()
        #expect(!model.shown.isEmpty)
        #expect(model.shown.count < model.items.count)
    }
}
