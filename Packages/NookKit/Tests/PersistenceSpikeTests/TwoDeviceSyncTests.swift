import Foundation
import Models
import SwiftData
import Testing

/// PRD 11.7's two-device test: both devices edit offline, reconnect in both orders, deliveries
/// repeat, and nothing is duplicated, lost or silently overwritten (Phase 20a).
struct TwoDeviceSyncTests {
    enum Order: String, CaseIterable, Sendable {
        case firstThenSecond
        case secondThenFirst
    }

    static let pieces = [
        Garment(id: "g-coat", name: "Camel coat", category: .layer, addedAt: SpikeSeed.epoch),
        Garment(id: "g-jeans", name: "Mid-wash jeans", category: .bottom, addedAt: SpikeSeed.epoch),
        Garment(id: "g-flats", name: "Navy flats", category: .shoes, addedAt: SpikeSeed.epoch),
    ]

    /// Two devices that have both synced the same three pieces, then gone offline.
    struct Pair {
        let zone = SpikeCloudZone()
        let first: SpikeSyncDevice
        let second: SpikeSyncDevice
        let locations: [SpikeStoreLocation]

        init() async throws {
            let one = try SpikeStoreLocation.temporary("device-1")
            let two = try SpikeStoreLocation.temporary("device-2")
            locations = [one, two]
            first = SpikeSyncDevice(modelContainer: try SpikeMigrationCoordinator(location: one).container())
            second = SpikeSyncDevice(modelContainer: try SpikeMigrationCoordinator(location: two).container())
            for piece in TwoDeviceSyncTests.pieces { try await first.create(piece) }
            try await first.sendChanges(to: zone)
            try await second.fetchChanges(from: zone)
        }

        /// Reconnects: each device sends, then both fetch, in the order given, until nothing is
        /// pending. Returns the number of rounds.
        @discardableResult
        func reconnect(_ order: Order) async throws -> Int {
            let devices = order == .firstThenSecond ? [first, second] : [second, first]
            for round in 1...5 {
                for device in devices {
                    try await device.fetchChanges(from: zone)
                    try await device.sendChanges(to: zone)
                }
                for device in devices { try await device.fetchChanges(from: zone) }
                let pending = try await first.state().pending.count + second.state().pending.count
                if pending == 0 { return round }
            }
            Issue.record("Still pending after five rounds")
            return 5
        }

        /// Both devices and the server hold the same pieces.
        func expectConverged() async throws {
            // Sorted here: SwiftData sorts strings with a localized, number-aware comparison
            // ("70fb" before "561b"), not in code-point order.
            let one = try await first.garments().sorted { $0.id < $1.id }
            let two = try await second.garments().sorted { $0.id < $1.id }
            let server = try await zone.garments()
            #expect(one == two)
            #expect(one == server)
            #expect(Set(one.map(\.id)).count == one.count)
        }

        func remove() {
            for location in locations { location.remove() }
        }
    }

    @Test func bothDevicesStartTheSame() async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        try await pair.expectConverged()
        #expect(try await pair.second.garments().count == 3)
    }

    @Test(arguments: Order.allCases)
    func editsToDifferentFieldsBothLand(_ order: Order) async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        try await pair.first.edit("g-coat") { $0.name = "Long camel coat" }
        try await pair.second.edit("g-coat") { $0.brand = "Uniqlo" }
        try await pair.reconnect(order)
        try await pair.expectConverged()
        let coat = try #require(try await pair.first.garments().first { $0.id == "g-coat" })
        #expect(coat.name == "Long camel coat")
        #expect(coat.brand == "Uniqlo")
        #expect(try await pair.first.state().conflicts.isEmpty)
        #expect(try await pair.second.state().conflicts.isEmpty)
    }

    /// The same field changed on both: one value is kept on both devices, and the other is kept
    /// as a conflict to review, whichever device reconnects first.
    @Test(arguments: Order.allCases)
    func theSameFieldChangedTwiceKeepsBothValues(_ order: Order) async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        try await pair.first.edit("g-jeans") { $0.name = "Work jeans" }
        try await pair.second.edit("g-jeans") { $0.name = "Weekend jeans" }
        try await pair.reconnect(order)
        try await pair.expectConverged()
        let kept = try #require(try await pair.first.garments().first { $0.id == "g-jeans" }).name
        let conflicts = try await pair.first.state().conflicts + pair.second.state().conflicts
        #expect(conflicts.count == 1)
        let conflict = try #require(conflicts.first)
        #expect(conflict.field == "name")
        #expect(Set([conflict.kept, conflict.competing]) == ["Work jeans", "Weekend jeans"])
        #expect(conflict.kept == kept)
        // The first to reach the server is kept: no device clock decides.
        #expect(kept == (order == .firstThenSecond ? "Work jeans" : "Weekend jeans"))
    }

    /// Recently deleted on one device, edited on the other: it stays deleted, and the edit to
    /// another field isn't lost.
    @Test(arguments: Order.allCases)
    func aDeletionBeatsAStaleEditWithoutLosingIt(_ order: Order) async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        try await pair.first.edit("g-flats") { $0.deletedAt = SpikeSeed.epoch }
        try await pair.second.edit("g-flats") { $0.notes = "Resoled in May" }
        try await pair.reconnect(order)
        try await pair.expectConverged()
        let flats = try #require(try await pair.second.garments().first { $0.id == "g-flats" })
        #expect(flats.isDeleted)
        #expect(flats.notes == "Resoled in May")
    }

    /// Restrictions win when both change: unavailable beats available, dirty beats clean, no
    /// longer owned beats owned. The other value is kept for review.
    @Test(arguments: Order.allCases)
    func competingRestrictionsStayRestricted(_ order: Order) async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        let back = SpikeSeed.epoch.addingTimeInterval(7 * 86_400)
        try await pair.first.edit("g-coat") { $0.availability = .unavailable(until: back) }
        try await pair.second.edit("g-coat") { $0.availability = .unavailable(until: nil) }
        try await pair.first.edit("g-jeans") { $0.ownership = .noLongerOwned }
        try await pair.second.edit("g-jeans") { $0.ownership = .purchased(.arrived) }
        try await pair.reconnect(order)
        try await pair.expectConverged()
        let garments = try await pair.first.garments()
        let coat = try #require(garments.first { $0.id == "g-coat" })
        let jeans = try #require(garments.first { $0.id == "g-jeans" })
        if case .unavailable = coat.availability {} else { Issue.record("The coat became available") }
        #expect(jeans.ownership == .noLongerOwned)
        let conflicts = try await pair.first.state().conflicts + pair.second.state().conflicts
        #expect(Set(conflicts.map(\.field)) == ["availability", "ownership"])
    }

    @Test(arguments: Order.allCases)
    func wearDaysFromBothDevicesAreKept(_ order: Order) async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        let monday = SpikeSeed.epoch
        let tuesday = monday.addingTimeInterval(86_400)
        try await pair.first.edit("g-coat") { $0.wornOn.append(monday) }
        try await pair.second.edit("g-coat") { $0.wornOn.append(tuesday) }
        try await pair.reconnect(order)
        try await pair.expectConverged()
        #expect(try await pair.first.garments().first { $0.id == "g-coat" }?.wornOn == [monday, tuesday])
    }

    @Test(arguments: Order.allCases)
    func piecesAddedOfflineOnBothDevicesAppearOnceEach(_ order: Order) async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        try await pair.first.create(Garment(id: .random(), name: "Silk scarf", category: .accessory, addedAt: .now))
        try await pair.second.create(Garment(id: .random(), name: "Rain boots", category: .shoes, addedAt: .now))
        try await pair.reconnect(order)
        try await pair.expectConverged()
        #expect(try await pair.first.garments().count == 5)
    }

    /// Deleted for good on one device, edited on the other: it never comes back, and the edit
    /// is reported rather than silently dropped.
    @Test(arguments: Order.allCases)
    func aPieceDeletedForGoodNeverComesBack(_ order: Order) async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        try await pair.first.purge("g-flats")
        try await pair.second.edit("g-flats") { $0.name = "Navy ballet flats" }
        try await pair.reconnect(order)
        try await pair.expectConverged()
        #expect(try await pair.first.garments().contains { $0.id == "g-flats" } == false)
        #expect(await pair.zone.purgedNames() == ["g-flats"])
        if order == .secondThenFirst {
            // The edit reached the server first; the deletion still won when it arrived.
            #expect(try await pair.second.state().conflicts.isEmpty)
        } else {
            #expect(try await pair.second.state().conflicts.map(\.field) == ["deleted for good"])
        }
    }

    /// A crash between applying fetched records and saving the new state: the next fetch
    /// delivers the same changes again, and applying them twice changes nothing.
    @Test func aRepeatedDeliveryChangesNothing() async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        try await pair.first.edit("g-coat") { $0.name = "Long camel coat" }
        try await pair.first.create(Garment(id: "g-scarf", name: "Silk scarf", category: .accessory, addedAt: .now))
        try await pair.first.sendChanges(to: pair.zone)

        let tokenBefore = try await pair.second.state().token
        await #expect(throws: SimulatedKill.self) {
            try await SpikeCheckpoint.$handler.withValue(
                { name in
                    if name == "sync.beforeStateUpdate" { throw SimulatedKill(checkpoint: name) }
                },
                operation: {
                    try await pair.second.fetchChanges(from: pair.zone)
                })
        }
        // The records were saved, but the state wasn't: it's behind, never ahead.
        #expect(try await pair.second.state().token == tokenBefore)
        let afterCrash = try await pair.second.garments()
        #expect(afterCrash.count == 4)

        // The next launch, on the same store.
        let relaunched = SpikeSyncDevice(modelContainer: pair.second.modelContainer)
        try await relaunched.fetchChanges(from: pair.zone)
        try await relaunched.fetchChanges(from: pair.zone)
        #expect(try await relaunched.garments() == afterCrash)
        #expect(try await relaunched.state().conflicts.isEmpty)
        #expect(try await relaunched.state().token > tokenBefore)
    }

    /// D8(d): the engine's state is a row in the store itself, so it's in the same SQLite file
    /// as the closet and takes the store's file protection. There is no separate state file.
    @Test func theSyncStateLivesInsideTheStore() async throws {
        let pair = try await Pair()
        defer { pair.remove() }
        let rows = try SpikeSQLite.rows(in: pair.locations[1].storeURL, "SELECT ZKEY FROM ZSYNCSTATERECORD")
        #expect(rows.contains { $0.first == "engine" })
        #expect(rows.contains { $0.first == "meta:g-coat" })
        let files = try FileManager.default.contentsOfDirectory(atPath: pair.locations[1].directory.path)
        #expect(Set(files).subtracting(["Closet.store", "Closet.store-wal", "Closet.store-shm", "Images"]).isEmpty)
    }
}
