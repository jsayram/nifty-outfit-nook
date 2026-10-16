import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// A model loaded from a fixture set, the way the screen loads it.
@MainActor
func loadedClosetModel(
    _ set: FixtureSet,
    behavior: FixtureBehavior = .normal,
    laundry: FixtureLaundryState? = nil,
    searchDelay: Duration = .milliseconds(250)
) async -> ClosetModel {
    let services = FixtureServices.make(
        set: set, behavior: behavior, laundry: laundry, now: TestTime.now, calendar: TestTime.calendar)
    let model = ClosetModel(searchDelay: searchDelay)
    await model.load(from: services, now: TestTime.now)
    return model
}

/// What Closet shows for each fixture set (RD-13, RD-11, LR-16).
@MainActor
struct ClosetModelLoadingTests {
    @Test func theDemoClosetShowsHerPiecesNewestFirst() async {
        let model = await loadedClosetModel(.demo)
        #expect(model.phase == .loaded)
        // 21 garments less the wishlist, no-longer-owned, archived and deleted ones.
        #expect(model.items.count == 17)
        #expect(model.shown == model.items)
        #expect(model.items.first?.id == "g-cream-crop")
        #expect(!model.items.contains { $0.id == "g-camel-trench" || $0.id == "g-gray-blazer" })
        #expect(model.deletedCount == 1)
        #expect(model.countText == "17 pieces")
        #expect(!model.isEmpty)
    }

    @Test func suitcasesAreTheActiveOnesByName() async {
        let model = await loadedClosetModel(.demo)
        #expect(model.suitcases.map(\.name) == ["Beach", "Gym", "Jose's house", "Spring trip", "Weekend"])
        // LR-11.1: a piece in two suitcases lists both names.
        let sneakers = model.items.first { $0.id == "g-white-sneakers" }
        #expect(sneakers?.suitcaseNames.sorted() == ["Beach", "Gym", "Weekend"])
        #expect(model.items.first { $0.id == "g-black-heels" }?.isPacked == false)
        // The archived Old dorm suitcase doesn't count.
        #expect(!model.items.contains { $0.suitcaseNames.contains("Old dorm") })
    }

    /// RD-11.1: with tracking off nothing says Dirty, though the marks are kept.
    @Test func laundryTrackingOffHidesDirty() async {
        let model = await loadedClosetModel(.demo)
        #expect(!model.tracksLaundry)
        #expect(model.dirtyCount == 0)
        #expect(!model.items.contains { $0.isDirty })
        model.toggleDirty()
        #expect(model.filter.laundry == nil)
    }

    @Test func laundryTrackingOnShowsDirtyPieces() async {
        let model = await loadedClosetModel(.demo, laundry: .some)
        #expect(model.tracksLaundry)
        #expect(model.dirtyCount == 2)
        model.toggleDirty()
        #expect(Set(model.shown.map(\.id)) == ["g-lace-top", "g-black-tee"])
        model.toggleDirty()
        #expect(model.shown.count == 17)
    }

    @Test func swatchesAreTheColoursInHerCloset() async {
        let model = await loadedClosetModel(.demo)
        #expect(
            model.colorChoices == [
                .black, .white, .cream, .beige, .tan, .brown, .navy, .blue, .denim, .olive, .brick, .burgundy, .pink,
            ])
        #expect(model.pieceKinds == ClosetModel.standardKinds)
    }

    /// The large closet has accessories, so their chip joins LR-09's six.
    @Test func accessoriesGetAChipWhenSheHasSome() async {
        let model = await loadedClosetModel(.large)
        #expect(model.items.count > 2_000)
        #expect(model.pieceKinds == ClosetModel.standardKinds + [.accessory])
    }

    @Test func anEmptyClosetSaysSo() async {
        let model = await loadedClosetModel(.empty)
        #expect(model.isEmpty)
        #expect(model.countText == "No pieces yet")
        #expect(model.colorChoices.isEmpty)
        #expect(model.deletedCount == 0)
    }

    @Test func aFailingStoreShowsTheErrorState() async {
        let model = await loadedClosetModel(.demo, behavior: .storesFail)
        #expect(model.phase == .failed)
        #expect(model.items.isEmpty)
        #expect(model.countText == "")
    }

    /// Without real services (a preview), Closet shows its error state, not an empty closet.
    @Test func noServicesIsAFailure() async {
        let model = ClosetModel()
        await model.load(from: .unavailable)
        #expect(model.phase == .failed)
        #expect(!model.isEmpty)
    }
}

/// Chips, swatches, the Suitcase filter and search, alone and together (LR-09.1, LR-11.2,
/// LR-11.3).
@MainActor
struct ClosetModelFilterTests {
    private func ids(_ model: ClosetModel) -> Set<Garment.ID> { Set(model.shown.map(\.id)) }

    @Test func pieceChipsCombineWithEachOther() async {
        let model = await loadedClosetModel(.demo)
        model.toggle(.shoes)
        #expect(ids(model) == ["g-nude-flats", "g-black-heels", "g-white-sneakers", "g-tan-loafers"])
        model.toggle(.bag)
        #expect(model.shown.count == 5)
        model.toggle(.shoes)
        #expect(ids(model) == ["g-burgundy-bag"])
    }

    @Test func swatchesCombineWithChips() async {
        let model = await loadedClosetModel(.demo)
        model.toggle(.black)
        #expect(ids(model) == ["g-black-tee", "g-black-heels"])
        model.toggle(.shoes)
        #expect(ids(model) == ["g-black-heels"])
        #expect(model.countText == "1 of 17 pieces")
        #expect(model.filterSummary == "Shoes · Black")
    }

    @Test func theSuitcaseFilter() async {
        let model = await loadedClosetModel(.demo)
        model.setPacking(.suitcase("s-weekend"))
        #expect(model.shown.count == 8)
        #expect(model.packingTitle == "Weekend")
        model.setPacking(.notPacked)
        #expect(ids(model) == ["g-black-heels", "g-tan-loafers", "g-burgundy-bag", "g-cream-crop"])
        #expect(model.packingTitle == "Not packed")
        model.setPacking(.inASuitcase)
        #expect(model.shown.count == 13)
        model.setPacking(.suitcase("s-spring"))
        #expect(model.shown.isEmpty)
        #expect(model.hasNoMatches)
    }

    @Test func searchMatchesNamesColoursKindsAndSuitcases() async {
        let model = await loadedClosetModel(.demo)
        model.searchText = "navy"
        model.applySearchNow()
        #expect(ids(model) == ["g-navy-trousers", "g-navy-cardigan"])
        model.searchText = "jose"
        model.applySearchNow()
        #expect(model.shown.count == 5)
        // A kind word from the chips, and a colour family that isn't in the name.
        model.searchText = "shoes"
        model.applySearchNow()
        #expect(model.shown.count == 4)
        model.searchText = "denim"
        model.applySearchNow()
        #expect(ids(model) == ["g-wide-jeans"])
        model.searchText = "weekend shoe"
        model.applySearchNow()
        #expect(ids(model) == ["g-white-sneakers"])
    }

    @Test func searchCombinesWithFiltersAndClearResetsEverything() async {
        let model = await loadedClosetModel(.demo)
        model.toggle(.layer)
        model.searchText = "navy"
        model.applySearchNow()
        #expect(ids(model) == ["g-navy-cardigan"])
        model.toggle(.pink)
        #expect(model.hasNoMatches)
        #expect(model.filterSummary == "Layers · Pink · “navy”")
        model.clearFilters()
        #expect(model.filter == GarmentFilter())
        #expect(model.searchText.isEmpty)
        #expect(model.shown.count == 17)
        #expect(model.countText == "17 pieces")
    }

    /// A suitcase that's gone after a reload stops filtering, rather than showing nothing.
    @Test func aMissingSuitcaseDropsOutOfTheFilter() async {
        let model = await loadedClosetModel(.demo)
        model.setPacking(.suitcase("s-gone"))
        let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        model.show(data.garments, suitcases: data.suitcases, profile: data.profile, now: TestTime.now)
        #expect(model.filter.packing == .any)
        #expect(model.shown.count == 17)
    }
}

/// Typed search waits for a pause, so the large closet isn't filtered on every letter.
@MainActor
struct ClosetSearchDelayTests {
    @Test func typingQuicklyRunsOneSearch() async {
        let model = await loadedClosetModel(.demo, searchDelay: .milliseconds(80))
        for text in ["n", "na", "nav", "navy"] {
            model.searchText = text
        }
        // Nothing has run yet.
        #expect(model.shown.count == 17)
        #expect(model.searchesApplied == 0)
        await model.settleSearch()
        #expect(model.searchesApplied == 1)
        #expect(model.filter.query == "navy")
        #expect(model.shown.count == 2)
    }

    @Test func emptyingTheFieldShowsEverythingAtOnce() async {
        let model = await loadedClosetModel(.demo, searchDelay: .seconds(30))
        model.searchText = "navy"
        model.applySearchNow()
        #expect(model.shown.count == 2)
        model.searchText = ""
        #expect(model.shown.count == 17)
    }

    @Test func pressingSearchDoesNotWait() async {
        let model = await loadedClosetModel(.demo, searchDelay: .seconds(30))
        model.searchText = "olive"
        model.applySearchNow()
        #expect(model.shown.map(\.id) == ["g-olive-trousers"])
        #expect(model.searchesApplied == 1)
    }
}

/// What VoiceOver reads on a piece (LR-10, LR-11.1, RD-11).
struct ClosetItemSpeechTests {
    private let calendar = TestTime.calendar
    private let now = TestTime.now
    private let locale = TestTime.locale

    private func item(dirty: Bool = false, suitcases: [String] = [], worn: [Int] = []) -> ClosetItem {
        let garment = Garment(
            id: "g-test", name: "Black wide-leg trousers", category: .bottom, colors: [.black],
            laundry: dirty ? .dirty : .clean, wornOn: worn.map(TestTime.day), addedAt: TestTime.day(-90))
        return ClosetItem(garment, suitcaseNames: suitcases, tracksLaundry: true)
    }

    @Test func readsDirtySuitcasesAndLastWorn() {
        let spoken = item(dirty: true, suitcases: ["Weekend", "Jose's house"], worn: [-30, -3])
            .spokenDetails(now: now, calendar: calendar, locale: locale)
        #expect(spoken == "Dirty, In Weekend and Jose's house, Last worn 3 days ago")
    }

    @Test func aPieceWithNothingToSayIsQuiet() {
        #expect(item().spokenDetails(now: now, calendar: calendar, locale: locale).isEmpty)
    }

    @Test func dirtyOnlyCountsWhileTracking() {
        let garment = Garment(id: "g-x", name: "Tee", category: .top, laundry: .dirty, addedAt: now)
        #expect(!ClosetItem(garment, suitcaseNames: [], tracksLaundry: false).isDirty)
        #expect(ClosetItem(garment, suitcaseNames: [], tracksLaundry: true).isDirty)
    }

    @Test func lastWornWords() {
        func text(_ offset: Int) -> String {
            LastWornText.describe(TestTime.day(offset), now: now, calendar: calendar, locale: locale)
        }
        #expect(text(0) == "Last worn today")
        #expect(text(-1) == "Last worn yesterday")
        #expect(text(-6) == "Last worn 6 days ago")
        #expect(text(-7) == "Last worn Oct 7")
        #expect(text(-300) == "Last worn Dec 18, 2025")
    }
}
