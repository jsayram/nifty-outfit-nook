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
        #expect(model.savedLookNames == ["Interview navy and pink", "Office navy and lace", "Taupe blazer office"])
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
    /// Delete now (PRD §7.4, Phase 21a): the preview says what goes, then the piece is gone for
    /// good with its unsaved Edit, and saved looks and suitcases keep their other pieces.
    @Test func deleteNowShowsWhatGoesThenDeletesForGood() async throws {
        let services = garmentTestServices()
        try await services.closet.delete("g-navy-trousers", at: TestTime.now)
        let edit = GarmentDraft(
            target: .garment("g-navy-trousers"), step: .details, details: GarmentDetails(name: "Navy work trousers"),
            base: GarmentDetails(name: "Navy dress pants"), savedAt: TestTime.now)
        try await services.drafts.save(edit)
        let model = RecentlyDeletedModel()
        await model.load(from: services, now: TestTime.now)

        try await model.askToDeletePermanently("g-navy-trousers", in: services)
        let preview = try #require(model.confirming)
        #expect(preview.piece.id == "g-navy-trousers")
        #expect(preview.hasUnsavedEdit)
        #expect(!preview.savedLooks.isEmpty)
        #expect(preview.suitcases.map(\.id).contains(DemoClosetIDs.josesHouse))
        let looksBefore = try await services.looks.looks()

        let name = try await model.deletePermanently(preview, in: services)
        #expect(name == "Navy dress pants")
        #expect(model.confirming == nil)
        #expect(model.pieces.map(\.id) == ["g-gray-leggings"])
        await #expect(throws: StoreError.notFound) { try await services.closet.garment("g-navy-trousers") }
        #expect(try await services.drafts.draft(for: .garment("g-navy-trousers")) == nil)
        #expect(try await services.looks.looks() == looksBefore)
    }

    /// The words of the question name everything that goes, and what stays.
    @Test func theQuestionSaysWhatGoesAndWhatStays() throws {
        let piece = Garment(
            id: "g1", name: "Navy dress pants", category: .bottom, photo: .sample("navy"), addedAt: TestTime.now)
        let look = Look(
            id: "l1", pieces: [LookPiece(id: "p1", content: .garment("g1"))], name: "Office navy", isSaved: true,
            createdAt: TestTime.now)
        let suitcase = Suitcase(id: "s1", name: "Weekend", garmentIDs: ["g1"], createdAt: TestTime.now)
        let preview = PermanentDeletionPreview(
            piece: piece, savedLooks: [look], suitcases: [suitcase], hasUnsavedEdit: true, pictureCount: 1)
        let message = RecentlyDeletedText.confirmMessage(preview)
        #expect(message.contains("Its photo and details are deleted from this iPhone. This can’t be undone."))
        #expect(message.contains("Your unsaved changes to it go too."))
        #expect(message.contains("Saved looks that use it keep their other pieces: Office navy."))
        #expect(message.contains("It comes out of Weekend."))
        #expect(message.contains("Try-on pictures with it in stay until you delete them."))

        let bare = RecentlyDeletedText.confirmMessage(
            PermanentDeletionPreview(
                piece: Garment(id: "g2", name: "Socks", category: .accessory, addedAt: TestTime.now)))
        #expect(bare == "Its details are deleted from this iPhone. This can’t be undone.")
    }

    @Test func aFailedDeleteNowKeepsThePiece() async throws {
        let services = garmentTestServices()
        let model = RecentlyDeletedModel()
        await model.load(from: services, now: TestTime.now)
        try await model.askToDeletePermanently("g-gray-leggings", in: services)
        let preview = try #require(model.confirming)
        let failing = garmentTestServices(behavior: .storesFail)
        await #expect(throws: StoreError.unavailable) { try await model.deletePermanently(preview, in: failing) }
        #expect(model.pieces.map(\.id) == ["g-gray-leggings"])
        #expect(model.deleting == nil)
        #expect(try await services.closet.garment("g-gray-leggings").isDeleted)
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
