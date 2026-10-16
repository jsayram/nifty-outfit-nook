import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// A screen's loads overlap: `.task`, a pushed screen closing, Undo and Try again each start one.
/// An older load that finishes last must not put back what it read before a change
/// (`LoadGeneration`). Each test holds an older load's read, changes the data, lets a newer load
/// finish, then lets the older one go.
@MainActor
struct StaleLoadTests {
    private func services() -> (NookServices, HeldClosetStore) {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let held = HeldClosetStore(services.closet)
        services.closet = held
        return (services, held)
    }

    private let added = Garment(
        id: "g-added", name: "Sage cardigan", category: .layer, addedAt: TestTime.now.addingTimeInterval(60))

    @Test func closetKeepsTheNewestLoad() async throws {
        let (services, held) = services()
        let model = ClosetModel()
        await model.load(from: services, now: TestTime.now)
        let before = model.items.count

        await held.holdNextRead()
        let older = Task { await model.load(from: services, now: TestTime.now) }
        await held.waitForHeldRead()
        try await services.closet.save(added)
        await model.load(from: services, now: TestTime.now)
        #expect(model.items.count == before + 1)

        await held.release()
        await older.value
        #expect(model.items.count == before + 1)
        #expect(model.items.first?.id == "g-added")
    }

    @Test func savedLooksKeepTheNewestLoad() async throws {
        let (services, held) = services()
        let model = SavedLooksModel()
        await model.load(from: services, now: TestTime.now)
        let removed = try #require(model.items.first)

        await held.holdNextRead()
        let older = Task { await model.load(from: services, now: TestTime.now) }
        await held.waitForHeldRead()
        try await services.looks.update(removed.id) { $0.isSaved = false }
        await model.load(from: services, now: TestTime.now)
        #expect(model.item(removed.id) == nil)

        await held.release()
        await older.value
        #expect(model.item(removed.id) == nil)
    }

    @Test func garmentDetailKeepsTheNewestLoad() async throws {
        let (services, held) = services()
        let model = GarmentDetailModel(garmentID: "g-navy-trousers")
        await model.load(from: services, now: TestTime.now)

        await held.holdNextRead()
        let older = Task { await model.load(from: services, now: TestTime.now) }
        await held.waitForHeldRead()
        try await services.closet.update("g-navy-trousers") { $0.name = "Navy wide-leg trousers" }
        await model.load(from: services, now: TestTime.now)
        #expect(model.garment?.name == "Navy wide-leg trousers")

        await held.release()
        await older.value
        #expect(model.garment?.name == "Navy wide-leg trousers")
    }

    /// An older load that fails after a newer one has shown the closet doesn't turn the screen
    /// into its error state.
    @Test func anOlderFailureDoesNotHideANewerLoad() async throws {
        let (services, held) = services()
        let model = ClosetModel()
        await model.load(from: services, now: TestTime.now)
        var failing = services
        failing.suitcases = UnavailableSuitcases()

        await held.holdNextRead()
        let older = Task { await model.load(from: failing, now: TestTime.now) }
        await held.waitForHeldRead()
        await model.load(from: services, now: TestTime.now)
        await held.release()
        await older.value
        #expect(model.phase == .loaded)
    }
}

/// A suitcase store whose reads fail.
private struct UnavailableSuitcases: SuitcaseStore {
    func suitcases() async throws(StoreError) -> [Suitcase] { throw .unavailable }
    func suitcase(_ id: Suitcase.ID) async throws(StoreError) -> Suitcase { throw .unavailable }
    func create(name: String, icon: SuitcaseIcon, at date: Date) async throws(StoreError) -> Suitcase {
        throw .unavailable
    }
    func update(_ id: Suitcase.ID, _ change: @Sendable (inout Suitcase) -> Void) async throws(StoreError) -> Suitcase {
        throw .unavailable
    }
    func add(_ garmentIDs: [Garment.ID], to id: Suitcase.ID) async throws(StoreError) { throw .unavailable }
    func remove(_ garmentIDs: [Garment.ID], from id: Suitcase.ID) async throws(StoreError) { throw .unavailable }
    func markUsed(_ id: Suitcase.ID, at date: Date) async throws(StoreError) { throw .unavailable }
    func delete(_ id: Suitcase.ID) async throws(StoreError) { throw .unavailable }
    func restore(_ suitcase: Suitcase) async throws(StoreError) { throw .unavailable }
    func eraseAll() async throws(StoreError) { throw .unavailable }
}
