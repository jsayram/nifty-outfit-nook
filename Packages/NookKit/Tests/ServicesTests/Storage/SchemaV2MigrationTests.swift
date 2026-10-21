import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// The store's first real schema change (Phase 21c, version 1 to 2), on the store file the
/// Phase 21b build wrote (`Phase21bFixtures`): it migrates through the coordinator's journal with
/// every record intact, a crash at any step recovers, the new fields save and survive a relaunch,
/// and the 21b build would leave a version 2 store alone rather than open it.
struct SchemaV2MigrationTests {
    /// Every place the version 1 to 2 migration can stop, in order. The stage is lightweight, so
    /// there are no batches.
    static let checkpoints = [
        "journal.snapshotting", "snapshot.copied", "journal.snapshotTaken", "journal.migrating", "migration.finished",
        "journal.migrated", "verified", "journal.verified",
    ]

    /// The 21b store, copied into a test store folder.
    private static func phase21bStore(_ label: String) throws -> TemporaryStore {
        let store = try TemporaryStore(label)
        try store.location.makeDirectory()
        try FileManager.default.copyItem(
            at: try Phase21bFixtures.url("Nook-v1", "store"), to: store.location.storeURL)
        return store
    }

    /// Every row the 21b store held is in the migrated store, byte for byte, and reads through
    /// its value type; a garment reads with no other names and no type. Nothing else is there.
    private static func expectEveryRecordIntact(in container: ModelContainer) throws {
        let before = try Phase21bFixtures.rows()
        let after = try StoreRow.all(in: ModelContext(container))
        #expect(Set(after) == Set(before))
        #expect(before.count == 50)
        for row in after where row.kind == RecordKind.garment.rawValue {
            let garment = try RecordPayload.decode(Garment.self, from: row.payload, version: row.payloadVersion)
            #expect(garment.otherNames.isEmpty && garment.subKind == nil)
        }
        // Every kind decodes as a save would check it, as a backup reads it.
        #expect(try RestoreChecker.checked(after).count == before.count)
    }

    @Test func thePhase21bStoreIsVersionOne() throws {
        let store = try Self.phase21bStore("v1")
        #expect(MigrationCoordinator<NookMigrationPlan>(location: store.location).storedVersion() == 1)
        #expect(MigrationCoordinator<Phase21bPlan>(location: store.location).storedVersion() == 1)
    }

    @Test func itMigratesThroughTheJournalWithEveryRecordIntact() throws {
        let store = try Self.phase21bStore("migrate")
        let manifest = try StoreSQLite.manifest(of: store.location.storeURL)
        let coordinator = MigrationCoordinator<NookMigrationPlan>(location: store.location)
        guard case .ready(let container, let report) = coordinator.open() else {
            Issue.record("The 21b store didn't open")
            return
        }
        #expect(report.migratedFrom == 1)
        #expect(coordinator.storedVersion() == 2)
        let journal = try #require(try coordinator.readJournal())
        #expect(journal.step == .verified && journal.from == 1 && journal.to == 2)
        #expect(journal.manifest == manifest)
        #expect(MigrationCoordinator<NookMigrationPlan>.verify(container, against: manifest).isEmpty)
        try Self.expectEveryRecordIntact(in: container)
        // The safety copy from before is kept, out of device backups, for seven days.
        #expect(FileManager.default.fileExists(atPath: store.location.snapshotURL.path))
    }

    /// The app killed at any step of the real migration: the next launch puts the snapshot back
    /// if it needs to, migrates again, and every record is there, unchanged.
    @Test(arguments: Self.checkpoints)
    func recoversFromACrashAt(_ checkpoint: String) throws {
        let store = try Self.phase21bStore("crash")
        let coordinator = MigrationCoordinator<NookMigrationPlan>(location: store.location)
        let stopped: Bool
        do {
            let kill: @Sendable (String) throws -> Void = { name in
                if name == checkpoint { throw StoreCheckpoint.Kill(checkpoint: name) }
            }
            let outcome = try StoreCheckpoint.$handler.withValue(kill) { try coordinator.openThrowing() }
            if case .problem(.updateFailed) = outcome { stopped = true } else { stopped = false }
        } catch {
            stopped = true
        }
        #expect(stopped, "the first launch should have stopped at \(checkpoint)")

        guard case .ready(let container, _) = coordinator.open() else {
            Issue.record("The store didn't open after a crash at \(checkpoint)")
            return
        }
        #expect(coordinator.storedVersion() == 2)
        #expect(try coordinator.readJournal()?.step == .verified)
        try Self.expectEveryRecordIntact(in: container)
    }

    /// After the migration, other names and a type save through the app's own stores, survive a
    /// relaunch, and the edited record moves to payload version 2 while the rest stay as they were.
    @Test func theNewFieldsSaveAndSurviveARelaunch() async throws {
        let store = try Self.phase21bStore("fields")
        do {
            let storage = try store.open()
            try await storage.closet.update("g-navy-trousers") { garment in
                garment.otherNames = [" Work trousers ", "work TROUSERS", "Navy dress pants", "Interview pants"]
                garment.subKind = .trousers
            }
        }
        let storage = try store.open()
        let garment = try await storage.closet.garment("g-navy-trousers")
        // Trimmed, without repeats or the piece's own name.
        #expect(garment.otherNames == ["Work trousers", "Interview pants"])
        #expect(garment.subKind == .trousers)

        let rows = try StoreRow.all(in: ModelContext(storage.container))
        let edited = try #require(rows.first { $0.id == "garment/g-navy-trousers" })
        #expect(edited.payloadVersion == 2)
        let untouched = Set(try Phase21bFixtures.rows().filter { $0.id != edited.id })
        #expect(untouched.isSubset(of: Set(rows)))
    }

    /// The 21b build, which knows only version 1, finds a version 2 store newer than it and
    /// leaves it alone: never opened, migrated or reset (0004 section 7).
    @Test func thePhase21bBuildLeavesAVersionTwoStoreAlone() throws {
        let store = try Self.phase21bStore("downgrade")
        guard case .ready = MigrationCoordinator<NookMigrationPlan>(location: store.location).open() else {
            Issue.record("The store didn't migrate")
            return
        }
        let before = try StoreSQLite.manifest(of: store.location.storeURL)
        let old = MigrationCoordinator<Phase21bPlan>(location: store.location)
        #expect(old.storedVersion() == nil)
        guard case .problem(.newerVersion) = old.open() else {
            Issue.record("The 21b build would have opened a version 2 store")
            return
        }
        #expect(try StoreSQLite.manifest(of: store.location.storeURL) == before)
    }
}

/// The plan the Phase 21b build shipped with: version 1 only.
enum Phase21bPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
