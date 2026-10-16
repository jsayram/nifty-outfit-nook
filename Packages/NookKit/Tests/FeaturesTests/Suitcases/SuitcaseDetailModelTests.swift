import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// One suitcase (Phase 13): packing, removing with Undo, the source, archive and delete with Undo.
@MainActor
struct SuitcaseDetailModelTests {
    private let now = ClosetTestTime.now

    private func services(source: FixtureSourceState? = nil, laundry: FixtureLaundryState? = nil) -> NookServices {
        FixtureServices.make(set: .demo, laundry: laundry, source: source, now: now, calendar: ClosetTestTime.calendar)
    }

    private func loaded(_ id: Suitcase.ID, _ services: NookServices) async -> SuitcaseDetailModel {
        let model = SuitcaseDetailModel(suitcaseID: id)
        await model.load(from: services, now: now)
        return model
    }

    @Test func showsItsPiecesInHerCloset() async throws {
        let services = services()
        try await services.closet.update("g-lace-top") { $0.ownership = .noLongerOwned }
        let model = await loaded("s-jose", services)
        #expect(model.phase == .loaded)
        // LR-16.1: the lace top is out of her closet, so it isn't shown.
        #expect(Set(model.items.map(\.id)) == ["g-navy-trousers", "g-pink-blouse", "g-navy-cardigan", "g-nude-flats"])
        #expect(!model.isSource)
        #expect(model.sourceName == "Main closet")
        // VoiceOver hears the other suitcases a piece is in.
        let trousers = try #require(model.items.first { $0.id == "g-navy-trousers" })
        #expect(trousers.suitcaseNames == ["Weekend"])
    }

    @Test func packAndUnpackOnTheSheet() async throws {
        let services = services()
        let model = await loaded("s-spring", services)
        #expect(model.items.isEmpty)
        #expect(try await model.togglePacked("g-tan-loafers", in: services, now: now))
        #expect(model.items.map(\.id) == ["g-tan-loafers"])
        #expect(model.isPacked("g-tan-loafers"))
        // The picker lists her whole closet, without Dirty badges.
        let list = model.packingList()
        #expect(list.items.count == 17)
        #expect(!(try await model.togglePacked("g-tan-loafers", in: services, now: now)))
        #expect(model.items.isEmpty)
    }

    @Test func removeThenUndo() async throws {
        let services = services()
        let model = await loaded("s-jose", services)
        try await model.remove("g-nude-flats", in: services, now: now)
        #expect(!model.isPacked("g-nude-flats"))
        #expect(model.pieceCount == 4)
        // It's still in her closet.
        #expect(try await services.closet.garment("g-nude-flats").isInCloset)
        try await model.putBack("g-nude-flats", in: services, now: now)
        #expect(model.pieceCount == 5)
    }

    @Test func useForStyleMeAndBack() async throws {
        let services = services()
        let model = await loaded("s-weekend", services)
        let previous = try await model.useForStyleMe(in: services, now: now)
        #expect(previous == .mainCloset)
        #expect(model.isSource)
        #expect(try await services.profile.profile().remembered.source == .suitcase("s-weekend"))
        #expect(try await services.suitcases.suitcase("s-weekend").lastUsedAt == now)
        try await model.setSource(.mainCloset, in: services, now: now)
        #expect(!model.isSource)
    }

    @Test func renameAndChangeThePicture() async throws {
        let services = services()
        let model = await loaded("s-gym", services)
        #expect(model.nameProblem("weekend") == .duplicate)
        #expect(model.nameProblem("Gym") == nil)
        try await model.edit(name: "Gym bag", icon: .duffel, in: services, now: now)
        #expect(model.suitcase?.name == "Gym bag")
        #expect(model.suitcase?.icon == .duffel)
    }

    @Test func deletingTheSourceGoesBackToTheMainClosetAndUndoPutsBothBack() async throws {
        let services = services(source: .suitcase)
        let model = await loaded("s-jose", services)
        #expect(model.isSource)
        let change = try #require(try await model.delete(in: services))
        #expect(change.wasSource)
        #expect(change.message == "Jose's house is deleted. Style Me now uses Main closet.")
        await #expect(throws: StoreError.notFound) { try await services.suitcases.suitcase("s-jose") }
        #expect(try await services.profile.profile().remembered.source == .mainCloset)
        // Its pieces stay in her closet.
        #expect(try await services.closet.garment("g-pink-blouse").isInCloset)

        try await change.undo(in: services)
        #expect(try await services.suitcases.suitcase("s-jose").garmentIDs.count == 5)
        #expect(try await services.profile.profile().remembered.source == .suitcase("s-jose"))
    }

    @Test func deletingAnotherSuitcaseLeavesTheSource() async throws {
        let services = services(source: .suitcase)
        let model = await loaded("s-beach", services)
        let change = try #require(try await model.delete(in: services))
        #expect(!change.wasSource)
        #expect(change.message == "Beach is deleted. Its pieces are still in your closet.")
        #expect(try await services.profile.profile().remembered.source == .suitcase("s-jose"))
    }

    @Test func archiveAndBringBack() async throws {
        let services = services(source: .suitcase)
        let model = await loaded("s-jose", services)
        let change = try #require(try await model.setArchived(true, in: services, now: now))
        #expect(model.isArchived)
        #expect(change.message == "Jose's house is archived. Style Me now uses Main closet.")
        #expect(try await services.profile.profile().remembered.source == .mainCloset)
        try await change.undo(in: services)
        #expect(try await !services.suitcases.suitcase("s-jose").isArchived)
        #expect(try await services.profile.profile().remembered.source == .suitcase("s-jose"))
    }

    @Test func aDeletedSuitcaseIsGone() async {
        let model = await loaded("s-missing", services())
        #expect(model.phase == .gone)
    }

    @Test func failingStoresShowTheError() async {
        let services = FixtureServices.make(set: .demo, behavior: .storesFail, now: now)
        let model = await loaded("s-jose", services)
        #expect(model.phase == .failed)
    }
}
