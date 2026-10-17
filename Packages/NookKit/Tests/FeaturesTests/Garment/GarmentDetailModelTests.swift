import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Fixture services on the fixed test clock, the way the screens get them.
@MainActor
func garmentTestServices(
    _ set: FixtureSet = .demo,
    behavior: FixtureBehavior = .normal,
    laundry: FixtureLaundryState? = nil
) -> NookServices {
    FixtureServices.make(
        set: set, behavior: behavior, laundry: laundry, now: TestTime.now, calendar: TestTime.calendar)
}

/// A detail model loaded from fixture services, the way the screen loads it.
@MainActor
func loadedDetailModel(_ id: Garment.ID, services: NookServices) async -> GarmentDetailModel {
    let model = GarmentDetailModel(garmentID: id)
    await model.load(from: services, now: TestTime.now)
    return model
}

/// What garment detail loads for each kind of piece (LR-11, LR-16, RD-11).
@MainActor
struct GarmentDetailLoadingTests {
    @Test func aPieceInTwoSuitcasesAndTwoSavedLooks() async {
        let model = await loadedDetailModel("g-navy-trousers", services: garmentTestServices())
        #expect(model.phase == .loaded)
        #expect(model.garment?.name == "Navy dress pants")
        // LR-11: every active suitcase it's in, by name.
        #expect(model.suitcases.map(\.name) == ["Jose's house", "Weekend"])
        // Saved looks only, newest first. Unsaved results don't count.
        #expect(model.savedLookNames == ["Interview navy and pink", "Office navy and lace", "Gray blazer office"])
        #expect(model.isInCloset)
        #expect(!model.tracksLaundry)
        #expect(!model.showsLaundryAction)
    }

    @Test func archivedSuitcasesDontCount() async {
        // Olive trousers are in Weekend and the archived Old dorm.
        let model = await loadedDetailModel("g-olive-trousers", services: garmentTestServices())
        #expect(model.suitcases.map(\.name) == ["Weekend"])
    }

    @Test func aPieceInNoSuitcaseOrLook() async {
        let model = await loadedDetailModel("g-black-heels", services: garmentTestServices())
        #expect(model.suitcases.isEmpty)
        #expect(model.savedLooks.map(\.id) == ["o-lace-date", "o-date-crop", "o-blazer-office"])
    }

    @Test func laundryTrackingShowsTheLaundryAction() async {
        let model = await loadedDetailModel("g-black-tee", services: garmentTestServices(laundry: .some))
        #expect(model.tracksLaundry)
        #expect(model.showsLaundryAction)
    }

    @Test func anUnknownPieceIsGone() async {
        let model = await loadedDetailModel("g-nothing", services: garmentTestServices())
        #expect(model.phase == .gone)
        #expect(model.garment == nil)
    }

    /// Deleted elsewhere: a piece in Recently deleted has no detail.
    @Test func aDeletedPieceIsGone() async {
        let model = await loadedDetailModel("g-gray-leggings", services: garmentTestServices())
        #expect(model.phase == .gone)
    }

    @Test func aFailingStoreShowsTheErrorState() async {
        let model = await loadedDetailModel("g-navy-trousers", services: garmentTestServices(behavior: .storesFail))
        #expect(model.phase == .failed)
    }

    @Test func noServicesIsAFailure() async {
        let model = GarmentDetailModel(garmentID: "g-navy-trousers")
        await model.load(from: .unavailable)
        #expect(model.phase == .failed)
        await #expect(throws: StoreError.unavailable) {
            try await model.toggleSuitcase("s-weekend", in: .unavailable)
        }
    }

    /// A piece she no longer has can be shown, but nothing can be done with it.
    @Test func aPieceSheNoLongerHasHasNoActions() async {
        let model = await loadedDetailModel("g-gray-blazer", services: garmentTestServices())
        #expect(model.phase == .loaded)
        #expect(!model.isInCloset)
        #expect(!model.showsLaundryAction)
    }
}

/// The changes garment detail makes, through the store (RD-11, LR-16).
@MainActor
struct GarmentDetailChangeTests {
    @Test func markDirtyThenUndo() async throws {
        let services = garmentTestServices(laundry: .clean)
        let model = await loadedDetailModel("g-navy-trousers", services: services)
        let previous = try await model.setLaundry(.dirty, in: services.closet)
        #expect(previous == .clean)
        #expect(model.garment?.laundry == .dirty)
        #expect(try await services.closet.garment("g-navy-trousers").laundry == .dirty)

        try await model.setLaundry(.clean, in: services.closet)
        #expect(try await services.closet.garment("g-navy-trousers").laundry == .clean)
    }

    /// LR-16.1: out of Closet and styling, kept with its links, and Undo brings it back.
    @Test func iDontHaveItAnyMoreThenUndo() async throws {
        let services = garmentTestServices()
        let model = await loadedDetailModel("g-navy-trousers", services: services)
        let removal = try #require(try await model.markNoLongerOwned(in: services.closet))
        #expect(removal.kind == .noLongerOwned(previous: .owned))
        #expect(removal.message == "Navy dress pants is out of your closet")

        let stored = try await services.closet.garment("g-navy-trousers")
        #expect(stored.ownership == .noLongerOwned)
        #expect(!stored.isInCloset)
        #expect(!Eligibility.isEligible(stored, members: nil, tracksLaundry: false, on: TestTime.now))
        // It stays in its suitcases and looks, so Undo needs nothing else.
        #expect(try await services.suitcases.suitcase(DemoClosetIDs.weekend).contains("g-navy-trousers"))
        let closet = await loadedClosetModel(services: services)
        #expect(!closet.items.contains { $0.id == "g-navy-trousers" })

        try await removal.undo(in: services.closet)
        #expect(try await services.closet.garment("g-navy-trousers").ownership == .owned)
        let after = await loadedClosetModel(services: services)
        #expect(after.items.contains { $0.id == "g-navy-trousers" })
    }

    /// Undo puts back the ownership it had, not just "owned".
    @Test func undoKeepsABoughtPieceBought() async throws {
        let services = garmentTestServices()
        try await services.closet.update("g-cream-crop") { $0.ownership = .purchased(.arrived) }
        let model = await loadedDetailModel("g-cream-crop", services: services)
        let removal = try #require(try await model.markNoLongerOwned(in: services.closet))
        try await removal.undo(in: services.closet)
        #expect(try await services.closet.garment("g-cream-crop").ownership == .purchased(.arrived))
    }

    /// LR-16.2 and LR-16.3: to Recently deleted, then restored with its links.
    @Test func deleteItThenRestoreFromRecentlyDeleted() async throws {
        let services = garmentTestServices()
        let model = await loadedDetailModel("g-navy-trousers", services: services)
        let removal = try #require(try await model.delete(in: services.closet, at: TestTime.now))
        #expect(removal.kind == .deleted)
        #expect(removal.message == "Navy dress pants is in Recently deleted")
        #expect(try await services.closet.garment("g-navy-trousers").deletedAt == TestTime.now)
        #expect(await loadedClosetModel(services: services).deletedCount == 2)

        let deleted = RecentlyDeletedModel()
        await deleted.load(from: services, now: TestTime.now)
        #expect(deleted.pieces.map(\.id) == ["g-navy-trousers", "g-gray-leggings"])

        let restored = try await deleted.restore("g-navy-trousers", in: services.closet)
        #expect(restored?.isDeleted == false)
        #expect(deleted.pieces.map(\.id) == ["g-gray-leggings"])
        let stored = try await services.closet.garment("g-navy-trousers")
        #expect(stored.isInCloset)
        #expect(stored.wornOn.count == 2)
        #expect(try await services.suitcases.suitcase(DemoClosetIDs.josesHouse).contains("g-navy-trousers"))
    }

    @Test func undoAfterDeleteRestores() async throws {
        let services = garmentTestServices()
        let model = await loadedDetailModel("g-black-heels", services: services)
        let removal = try #require(try await model.delete(in: services.closet, at: TestTime.now))
        try await removal.undo(in: services.closet)
        #expect(try await services.closet.garment("g-black-heels").isInCloset)
    }

    /// Only a piece in her closet can be removed.
    @Test func aPieceNotInTheClosetCantBeRemoved() async throws {
        let services = garmentTestServices()
        let model = await loadedDetailModel("g-gray-blazer", services: services)
        #expect(try await model.markNoLongerOwned(in: services.closet) == nil)
        #expect(try await model.delete(in: services.closet, at: TestTime.now) == nil)
        #expect(try await services.closet.garment("g-gray-blazer").deletedAt == nil)
    }

    @Test func aFailedSaveThrowsAndChangesNothing() async {
        let services = garmentTestServices()
        let model = await loadedDetailModel("g-navy-trousers", services: services)
        let failing = garmentTestServices(behavior: .storesFail)
        await #expect(throws: StoreError.unavailable) {
            try await model.markNoLongerOwned(in: failing.closet)
        }
        #expect(model.garment?.ownership == .owned)
        #expect(!model.isSaving)
    }
}

/// Recently deleted: newest deletion first, and the 30 days (PRD §7.4).
@MainActor
struct RecentlyDeletedModelTests {
    @Test func theDemoHasOneDeletedPiece() async {
        let model = RecentlyDeletedModel()
        await model.load(from: garmentTestServices(), now: TestTime.now)
        #expect(model.phase == .loaded)
        #expect(model.pieces.map(\.name) == ["Old gray leggings"])
        #expect(!model.isEmpty)
    }

    /// The leggings were deleted 3 days ago, so they go for good 27 days from now.
    @Test func piecesPastTheirThirtyDaysArePurgedOnLoad() async throws {
        let services = garmentTestServices()
        let model = RecentlyDeletedModel()
        await model.load(from: services, now: TestTime.day(26))
        #expect(model.pieces.count == 1)
        await model.load(from: services, now: TestTime.day(27))
        #expect(model.isEmpty)
        await #expect(throws: StoreError.notFound) {
            try await services.closet.garment("g-gray-leggings")
        }
    }

    @Test func anEmptyClosetHasNothingDeleted() async {
        let model = RecentlyDeletedModel()
        await model.load(from: garmentTestServices(.empty), now: TestTime.now)
        #expect(model.isEmpty)
    }

    @Test func aFailingStoreShowsTheErrorState() async {
        let model = RecentlyDeletedModel()
        await model.load(from: garmentTestServices(behavior: .storesFail), now: TestTime.now)
        #expect(model.phase == .failed)
    }
}

/// The demo's suitcase IDs, as the fixtures name them.
enum DemoClosetIDs {
    static let josesHouse: Suitcase.ID = "s-jose"
    static let weekend: Suitcase.ID = "s-weekend"
}

/// A closet model loaded from the same services, to check what Closet shows after a change.
@MainActor
func loadedClosetModel(services: NookServices) async -> ClosetModel {
    let model = ClosetModel()
    await model.load(from: services, now: TestTime.now)
    return model
}
