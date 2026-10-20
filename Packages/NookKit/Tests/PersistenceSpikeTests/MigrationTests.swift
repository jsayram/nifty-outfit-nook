import CoreData
import Foundation
import SwiftData
import Testing

/// PRD 11.7's migration gates on SwiftData: versioned fixtures, image hashes, interrupted
/// migrations at every step, unsupported schemas, free space and rollback (Phase 20a).
struct MigrationTests {
    static let counts = SpikeSeed.Counts(garments: 450, photoEvery: 4, looks: 60, suitcases: 6)

    /// Every place the migration can stop, in order. The V2 to V3 step saves three batches of
    /// 200 garments for 450.
    static let checkpoints = [
        "journal.snapshotting", "snapshot.copied", "journal.snapshotTaken", "journal.migrating",
        "didMigrate.batch.1", "didMigrate.batch.2", "didMigrate.batch.3", "migration.finished", "journal.migrated",
        "verified", "journal.verified",
    ]

    @Test func migratesAV1StoreAndVerifiesIt() throws {
        let location = try SpikeStoreLocation.temporary("migrate")
        defer { location.remove() }
        try SpikeSeed.makeV1Store(at: location, counts: Self.counts, imageBytes: 8_000)
        let coordinator = SpikeMigrationCoordinator(location: location)
        #expect(try coordinator.storedVersion() == .v1)
        let before = try SpikeSQLite.manifest(of: location.storeURL, images: location.imagesDirectory)

        guard case .ready(let container, let report) = try coordinator.open() else {
            Issue.record("Expected the store to open")
            return
        }
        #expect(report.migratedFrom == .v1)
        #expect(try coordinator.storedVersion() == .v3)
        #expect(try SpikeMigrationCoordinator.verify(container, against: before).isEmpty)
        #expect(try coordinator.readJournal()?.step == .verified)

        // The rename kept its values, and the new revision has its default.
        let context = ModelContext(container)
        let first = try #require(
            try context.fetch(FetchDescriptor<SpikeSchemaV3.GarmentRecord>(sortBy: [SortDescriptor(\.garmentID)]))
                .first)
        #expect(first.shadeNote == "mid-wash 0")
        #expect(first.revision == 0)
        #expect(first.images.first?.byteCount == 8_000)
    }

    /// A crash at any step leaves a store that the next launch recovers: the snapshot goes back,
    /// the migration runs again, and every ID, count, image hash and relationship matches.
    @Test(arguments: Self.checkpoints)
    func recoversFromACrashAt(_ checkpoint: String) throws {
        let location = try SpikeStoreLocation.temporary("crash")
        defer { location.remove() }
        try SpikeSeed.makeV1Store(at: location, counts: Self.counts, imageBytes: 8_000)
        let before = try SpikeSQLite.manifest(of: location.storeURL, images: location.imagesDirectory)
        let coordinator = SpikeMigrationCoordinator(location: location)

        let killed = Self.run(killedAt: checkpoint) { _ = try coordinator.open() }
        #expect(killed, "the run should have stopped at \(checkpoint)")

        // The next launch.
        guard case .ready(let container, let report) = try coordinator.open() else {
            Issue.record("Expected the store to open after a crash at \(checkpoint)")
            return
        }
        #expect(try SpikeMigrationCoordinator.verify(container, against: before).isEmpty)
        #expect(try coordinator.storedVersion() == .v3)
        #expect(try coordinator.readJournal()?.step == .verified)
        switch checkpoint {
        case "journal.snapshotting", "snapshot.copied":
            #expect(report.resumedAfter == .snapshotting)
            #expect(!report.snapshotRestored)
        case "verified", "journal.verified":
            // Killed after verifying but before or just after the journal said so.
            #expect(report.resumedAfter == .migrated || report.resumedAfter == .verified)
        default:
            #expect(report.snapshotRestored)
        }
    }

    /// What SwiftData does on its own when a custom stage stops half way: the store already has
    /// the new schema, holds only the batches saved before the stop, and opens as if migrated.
    /// This is why the journal and snapshot are needed.
    @Test func swiftDataAloneLeavesAHalfMigratedStoreThatOpensAsDone() throws {
        let location = try SpikeStoreLocation.temporary("raw")
        defer { location.remove() }
        try SpikeSeed.makeV1Store(at: location, counts: Self.counts, imageBytes: 8_000)
        let coordinator = SpikeMigrationCoordinator(location: location)
        let photos = Self.counts.garments / Self.counts.photoEvery + 1

        let killed = Self.run(killedAt: "didMigrate.batch.2") { _ = try coordinator.container() }
        #expect(killed)
        let version = try coordinator.storedVersion()
        let container = try coordinator.container()
        let images = try ModelContext(container).fetchCount(FetchDescriptor<SpikeSchemaV3.ImageAssetRecord>())
        // Recorded for the decision note; the assertions describe what the spike found.
        print("SPIKE raw half migration: version \(String(describing: version)), \(images) of \(photos) images")
        #expect(version == .v3)
        #expect(images < photos)
    }

    /// A store from a newer build is never migrated, opened or reset: the recovery path opens,
    /// and the file is byte for byte the same.
    @Test func aNewerStoreOpensTheRecoveryPathAndIsLeftAlone() throws {
        let location = try SpikeStoreLocation.temporary("newer")
        defer { location.remove() }
        // Through Core Data, for the same reason as `SpikeSeed.makeV1Store`.
        let model = try #require(
            NSManagedObjectModel.makeManagedObjectModel(for: Schema(versionedSchema: SpikeSchemaV4Future.self)))
        let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try storeCoordinator.addPersistentStore(type: .sqlite, at: location.storeURL)
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = storeCoordinator
        try context.performAndWait {
            let garment = NSEntityDescription.insertNewObject(forEntityName: "GarmentRecord", into: context)
            garment.setValue("g-1", forKey: "garmentID")
            garment.setValue("From the future", forKey: "name")
            try context.save()
        }
        try storeCoordinator.remove(store)
        let before = try Self.storeBytes(location)
        let coordinator = SpikeMigrationCoordinator(location: location)
        #expect(try coordinator.storedVersion() == nil)
        guard case .recovery(.unsupportedSchema) = try coordinator.open() else {
            Issue.record("Expected the recovery path")
            return
        }
        #expect(try Self.storeBytes(location) == before)
    }

    /// SwiftData itself, given a store newer than its plan, refuses to open it rather than
    /// wiping it. Recorded so a future SDK that changes this shows up as a failing test.
    @Test func swiftDataRefusesAStoreNewerThanItsPlanWithoutWipingIt() throws {
        let location = try SpikeStoreLocation.temporary("downgrade")
        defer { location.remove() }
        _ = try SpikeSeed.makeCurrentStore(at: location, counts: .small)
        let before = try SpikeSQLite.manifest(of: location.storeURL, images: location.imagesDirectory)
        var opened = false
        do {
            _ = try ModelContainer(
                for: Schema(versionedSchema: SpikeSchemaV2.self), migrationPlan: SpikeMigrationPlanToV2.self,
                configurations: [ModelConfiguration(url: location.storeURL)])
            opened = true
        } catch {
            print("SPIKE downgrade error: \(error)")
        }
        #expect(!opened)
        #expect(try SpikeSQLite.manifest(of: location.storeURL, images: location.imagesDirectory) == before)
    }

    @Test func notEnoughSpaceLeavesTheStoreAsItWas() throws {
        let location = try SpikeStoreLocation.temporary("space")
        defer { location.remove() }
        try SpikeSeed.makeV1Store(at: location, counts: .small, imageBytes: 8_000)
        var coordinator = SpikeMigrationCoordinator(location: location)
        coordinator.availableSpace = { 1_000 }
        guard case .recovery(.notEnoughSpace) = try coordinator.open() else {
            Issue.record("Expected the recovery path")
            return
        }
        #expect(try coordinator.storedVersion() == .v1)
        #expect(try coordinator.readJournal() == nil)
    }

    /// A photo file that disappears during the migration fails verification, and the snapshot
    /// goes back, so the store is V1 again with every record.
    @Test func aFailedVerificationPutsTheSnapshotBack() throws {
        let location = try SpikeStoreLocation.temporary("verify")
        defer { location.remove() }
        try SpikeSeed.makeV1Store(at: location, counts: .small, imageBytes: 8_000)
        let before = try SpikeSQLite.manifest(of: location.storeURL, images: location.imagesDirectory)
        let coordinator = SpikeMigrationCoordinator(location: location)
        let images = SpikeImageFiles(directory: location.imagesDirectory)
        let outcome = try SpikeCheckpoint.$handler.withValue({ name in
            if name == "journal.migrating" { try images.delete(SpikeImageFiles.fileName(forPhoto: "photo-g-00000")) }
        }) { try coordinator.open() }
        guard case .recovery(.verificationFailed(let problems)) = outcome else {
            Issue.record("Expected a failed verification")
            return
        }
        #expect(problems == ["g-00000 image hash differs"])
        #expect(try coordinator.storedVersion() == .v1)
        #expect(try SpikeSQLite.manifest(of: location.storeURL, images: location.imagesDirectory).garmentIDs == before.garmentIDs)
    }

    /// A migration that crashes on every launch stops after three tries, on the snapshot.
    @Test func aCrashLoopStopsOnTheSnapshot() throws {
        let location = try SpikeStoreLocation.temporary("loop")
        defer { location.remove() }
        try SpikeSeed.makeV1Store(at: location, counts: .small, imageBytes: 8_000)
        let coordinator = SpikeMigrationCoordinator(location: location)
        for _ in 0..<3 {
            #expect(Self.run(killedAt: "migration.finished") { _ = try coordinator.open() })
        }
        guard case .recovery(.migrationKeepsFailing) = try coordinator.open() else {
            Issue.record("Expected the recovery path")
            return
        }
        #expect(try coordinator.storedVersion() == .v1)
    }

    @Test func theSnapshotIsDeletedSevenDaysAfterAVerifiedUpgrade() throws {
        let location = try SpikeStoreLocation.temporary("cleanup")
        defer { location.remove() }
        try SpikeSeed.makeV1Store(at: location, counts: .small, imageBytes: 8_000)
        let start = Date.now
        var coordinator = SpikeMigrationCoordinator(location: location)
        coordinator.now = { start }
        _ = try coordinator.open()
        #expect(FileManager.default.fileExists(atPath: location.snapshotURL.path))
        coordinator.now = { start.addingTimeInterval(6 * 86_400) }
        _ = try coordinator.open()
        #expect(FileManager.default.fileExists(atPath: location.snapshotURL.path))
        coordinator.now = { start.addingTimeInterval(7 * 86_400) }
        _ = try coordinator.open()
        #expect(!FileManager.default.fileExists(atPath: location.snapshotURL.path))
        #expect(try coordinator.readJournal() == nil)
    }

    // MARK: Helpers

    /// Runs `body`, stopping it at `checkpoint` as if the process died there. True if it stopped.
    static func run(killedAt checkpoint: String, _ body: () throws -> Void) -> Bool {
        do {
            try SpikeCheckpoint.$handler.withValue({ name in
                if name == checkpoint { throw SimulatedKill(checkpoint: name) }
            }) { try body() }
            return false
        } catch {
            return true
        }
    }

    static func storeBytes(_ location: SpikeStoreLocation) throws -> [Data] {
        try ["", "-wal"].compactMap { suffix in
            let path = location.storeURL.path + suffix
            return FileManager.default.fileExists(atPath: path) ? try Data(contentsOf: URL(filePath: path)) : nil
        }
    }
}

/// A schema this build doesn't know, as a newer app would have written.
enum SpikeSchemaV4Future: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] { [GarmentRecord.self] }

    @Model
    final class GarmentRecord {
        @Attribute(.unique) var garmentID: String
        var name: String
        var subKind: String?

        init(garmentID: String, name: String) {
            self.garmentID = garmentID
            self.name = name
        }
    }
}
