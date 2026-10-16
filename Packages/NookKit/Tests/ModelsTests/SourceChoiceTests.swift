import Foundation
import Models
import NookTestSupport
import Testing

/// The source she's browsing from (FR-67, PRD §7.7, Phase 13).
struct SourceChoiceTests {
    private let packed: Suitcase = Suitcase(
        id: "s-trip", name: "Trip", garmentIDs: ["g-top", "g-gone", "g-deleted"], createdAt: TestTime.day(-9))
    private let archived = Suitcase(id: "s-old", name: "Old", isArchived: true, createdAt: TestTime.day(-90))

    private var garments: [Garment] {
        var gone = Make.garment("g-gone", .bottom, ownership: .noLongerOwned)
        gone.name = "Gone"
        var deleted = Make.garment("g-deleted", .shoes)
        deleted.deletedAt = TestTime.day(-1)
        return [Make.garment("g-top", .top), Make.garment("g-other", .bottom), gone, deleted]
    }

    @Test func aSuitcaseThatIsThereIsShown() {
        #expect(SourceChoice.shown(.suitcase("s-trip"), among: [packed]) == .suitcase("s-trip"))
        #expect(SourceChoice.shown(.mainCloset, among: [packed]) == .mainCloset)
    }

    @Test func aDeletedOrArchivedSuitcaseFallsBackToTheMainCloset() {
        // PRD §7.7: browsing goes back to the main closet.
        #expect(SourceChoice.shown(.suitcase("s-missing"), among: [packed]) == .mainCloset)
        #expect(SourceChoice.shown(.suitcase("s-old"), among: [packed, archived]) == .mainCloset)
        #expect(!SourceChoice.isAvailable(.suitcase("s-old"), among: [archived]))
        #expect(SourceChoice.isAvailable(.mainCloset, among: []))
    }

    @Test func piecesSheNoLongerHasAreHiddenInASuitcase() {
        // LR-16.1: the links stay in the data, but the pieces never show or count.
        let inTrip = SourceChoice.pieces(in: .suitcase("s-trip"), garments: garments, suitcases: [packed])
        #expect(inTrip.map(\.id) == ["g-top"])
        let inCloset = SourceChoice.pieces(in: .mainCloset, garments: garments, suitcases: [packed])
        #expect(inCloset.map(\.id) == ["g-top", "g-other"])
        #expect(SourceChoice.pieces(in: .suitcase("s-missing"), garments: garments, suitcases: [packed]).isEmpty)
    }
}

/// What Laundry lists and what Mark clean and Undo may change (RD-11, PRD §7.3, FR-65).
struct LaundryBasketTests {
    private var garments: [Garment] {
        var gone = Make.garment("g-gone", .bottom, ownership: .noLongerOwned, laundry: .dirty)
        gone.name = "Gone"
        var deleted = Make.garment("g-deleted", .shoes, laundry: .dirty)
        deleted.deletedAt = TestTime.day(-1)
        return [
            Make.garment("g-tee", .top, laundry: .dirty),
            Make.garment("g-jeans", .bottom, laundry: .dirty),
            Make.garment("g-clean", .top),
            gone, deleted,
        ]
    }

    @Test func listsOnlyDirtyPiecesInHerCloset() {
        let basket = LaundryBasket(garments: garments)
        #expect(basket.dirty.map(\.id) == ["g-tee", "g-jeans"])
        let suitcase = Suitcase(id: "s-1", name: "Gym", garmentIDs: ["g-tee", "g-gone"], createdAt: TestTime.now)
        #expect(basket.dirty(in: suitcase).map(\.id) == ["g-tee"])
    }

    @Test func markCleanSkipsWhatItMustNotChange() {
        // FR-65: only owned, non-Trash, dirty pieces; each once.
        let ids: [Garment.ID] = ["g-tee", "g-tee", "g-clean", "g-gone", "g-deleted", "g-missing", "g-jeans"]
        #expect(LaundryBasket.cleanable(ids, in: garments) == ["g-tee", "g-jeans"])
    }

    @Test func undoOnlyPutsBackPiecesThatAreStillClean() {
        var now = garments
        for index in now.indices where now[index].id == "g-tee" || now[index].id == "g-jeans" {
            now[index].laundry = .clean
        }
        // She marked the jeans dirty again elsewhere: Undo leaves them alone.
        if let jeans = now.firstIndex(where: { $0.id == "g-jeans" }) { now[jeans].laundry = .dirty }
        #expect(LaundryBasket.undoable(["g-tee", "g-jeans"], in: now) == ["g-tee"])
    }

    @Test func turningTrackingOnBringsTheMarksBack() {
        // RD-11.2: marks are kept while tracking is off; the hamper ignores them until it's on.
        #expect(HamperState(garments: garments, tracksLaundry: false) == .off)
        #expect(HamperState(garments: garments, tracksLaundry: true) == .toWash(2))
    }
}
