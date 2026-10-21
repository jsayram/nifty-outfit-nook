import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// Phase 21a's schema-change checkpoint, in code: a store with her data moves to a new schema
/// version with every record intact, a crash at any step recovers at the next launch, and a store
/// the app can't read is never opened or reset (PRD 11.7; the coordinator from the 20a spike).
struct MigrationCoordinatorTests {
    private static let demo = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)

    /// Every place a migration with the custom stage can stop, in order. The demo's 21 garments
    /// save in three batches of 10.
    static let checkpoints = [
        "journal.snapshotting", "snapshot.copied", "journal.snapshotTaken", "journal.migrating",
        "didMigrate.batch.1", "didMigrate.batch.2", "didMigrate.batch.3", "migration.finished", "journal.migrated",
        "verified", "journal.verified",
    ]

    /// A store at the app's version (2) holding the demo closet, made through the app's own stores.
    private static func seededStore(_ label: String) async throws -> (TemporaryStore, StoreManifest) {
        let store = try TemporaryStore(label)
        do {
            let storage = try store.open()
            for garment in demo.garments { try await storage.closet.save(garment) }
            for look in demo.looks { try await storage.looks.save(look) }
            for suitcase in demo.suitcases { try await storage.suitcases.restore(suitcase) }
            for picture in demo.pictures { try await storage.pictures.save(picture) }
            try await storage.profile.save(demo.profile)
            try await storage.onboarding.complete(startingCloset: .empty)
        }
        return (store, try StoreSQLite.manifest(of: store.location.storeURL))
    }

    /// Her data read back through the app's stores, on a migrated container.
    private static func expectDemoIntact(in container: ModelContainer) async throws {
        let storage = NookStorage(container: container, calendar: TestTime.calendar)
        #expect(try await storage.closet.garments().count == demo.garments.count)
        for garment in demo.garments {
            #expect(try await storage.closet.garment(garment.id) == (try StoreValidation.garment(garment)))
        }
        #expect(try await storage.looks.looks().count == demo.looks.count)
        #expect(Set(try await storage.suitcases.suitcases()) == Set(demo.suitcases))
        #expect(try await storage.profile.profile() == (try StoreValidation.profile(demo.profile)))
        #expect(try await storage.onboarding.state() == OnboardingState(isCompleted: true, startingCloset: .empty))
    }

    @Test func theAppsPlanIsAtVersionTwo() throws {
        #expect(MigrationCoordinator<NookMigrationPlan>.currentVersion == 2)
        let store = try TemporaryStore("version")
        _ = try store.open()
        #expect(MigrationCoordinator<NookMigrationPlan>(location: store.location).storedVersion() == 2)
    }

    @Test func aLightweightMigrationKeepsEveryRecord() async throws {
        let (store, before) = try await Self.seededStore("lightweight")
        let coordinator = MigrationCoordinator<LightweightPlanV3>(location: store.location)
        #expect(coordinator.storedVersion() == 2)
        guard case .ready(let container, let report) = coordinator.open() else {
            Issue.record("The store didn't open")
            return
        }
        #expect(report.migratedFrom == 2)
        #expect(coordinator.storedVersion() == 3)
        #expect(MigrationCoordinator<LightweightPlanV3>.verify(container, against: before).isEmpty)
        #expect(try coordinator.readJournal()?.step == .verified)
        try await Self.expectDemoIntact(in: container)
        // The safety copy is left out of device backups.
        let values = try store.location.recoveryDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func aCustomMigrationRunsItsStageAndKeepsEveryRecord() async throws {
        let (store, before) = try await Self.seededStore("custom")
        guard case .ready(let container, _) = MigrationCoordinator<CustomPlanV3>(location: store.location).open() else {
            Issue.record("The store didn't open")
            return
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MigrationProbe>()) == Self.demo.garments.count)
        #expect(MigrationCoordinator<CustomPlanV3>.verify(container, against: before).isEmpty)
        try await Self.expectDemoIntact(in: container)
    }

    /// The app killed at any step: the next launch puts the snapshot back if it needs to,
    /// migrates again, and every record is there, unchanged.
    @Test(arguments: Self.checkpoints)
    func recoversFromACrashAt(_ checkpoint: String) async throws {
        let (store, before) = try await Self.seededStore("crash")
        let coordinator = MigrationCoordinator<CustomPlanV3>(location: store.location)

        let stopped: Bool
        do {
            let kill: @Sendable (String) throws -> Void = { name in
                if name == checkpoint { throw StoreCheckpoint.Kill(checkpoint: name) }
            }
            let outcome = try StoreCheckpoint.$handler.withValue(kill) { try coordinator.openThrowing() }
            // SwiftData may hand a stop inside its own stage back as a failed migration.
            if case .problem(.updateFailed) = outcome { stopped = true } else { stopped = false }
        } catch {
            stopped = true
        }
        #expect(stopped, "the first launch should have stopped at \(checkpoint)")

        // The next launch.
        guard case .ready(let container, let report) = coordinator.open() else {
            Issue.record("The store didn't open after a crash at \(checkpoint)")
            return
        }
        #expect(MigrationCoordinator<CustomPlanV3>.verify(container, against: before).isEmpty)
        #expect(coordinator.storedVersion() == 3)
        #expect(try coordinator.readJournal()?.step == .verified)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MigrationProbe>()) == Self.demo.garments.count)
        switch checkpoint {
        case "journal.snapshotting", "snapshot.copied":
            #expect(report.resumedAfter == .snapshotting)
            #expect(!report.snapshotRestored)
        case "verified", "journal.verified":
            #expect(report.resumedAfter == .migrated || report.resumedAfter == .verified)
        default:
            #expect(report.snapshotRestored)
        }
        try await Self.expectDemoIntact(in: container)
    }

    /// A store from a newer app is never opened, migrated or reset: the file stays as it was.
    @Test func aNewerStoreIsLeftAlone() async throws {
        let store = try TemporaryStore("newer")
        guard case .ready(let container, _) = MigrationCoordinator<LightweightPlanV3>(location: store.location).open()
        else {
            Issue.record("The version 3 store wasn't made")
            return
        }
        let context = ModelContext(container)
        context.insert(
            StoredRecord(kind: "garment", key: "g1", payloadVersion: 1, payload: Data("{}".utf8), savedAt: .now))
        try context.save()
        let before = try StoreSQLite.manifest(of: store.location.storeURL)

        let app = MigrationCoordinator<NookMigrationPlan>(location: store.location)
        #expect(app.storedVersion() == nil)
        guard case .problem(.newerVersion) = app.open() else {
            Issue.record("The app opened a newer store")
            return
        }
        #expect(try StoreSQLite.manifest(of: store.location.storeURL) == before)
        #expect(try app.readJournal() == nil)
    }

    /// A file that isn't a store is never replaced.
    @Test func aDamagedStoreIsLeftAlone() throws {
        let store = try TemporaryStore("damaged")
        try store.location.makeDirectory()
        let junk = Data("not a store".utf8)
        try junk.write(to: store.location.storeURL)
        guard case .problem(.newerVersion) = MigrationCoordinator<NookMigrationPlan>(location: store.location).open()
        else {
            Issue.record("A damaged store was opened")
            return
        }
        #expect(try Data(contentsOf: store.location.storeURL) == junk)
    }

    /// Short of space for the safety copy: nothing starts, and the store is still version 2.
    @Test func notEnoughSpaceChangesNothing() async throws {
        let (store, before) = try await Self.seededStore("space")
        var coordinator = MigrationCoordinator<LightweightPlanV3>(location: store.location)
        coordinator.availableSpace = { 1_000 }
        guard case .problem(.notEnoughSpace) = coordinator.open() else {
            Issue.record("Expected not enough space")
            return
        }
        #expect(coordinator.storedVersion() == 2)
        #expect(try coordinator.readJournal() == nil)
        #expect(try StoreSQLite.manifest(of: store.location.storeURL) == before)
    }

    /// A migration that loses a record fails its check. The next launch puts the snapshot back
    /// before opening anything; after three tries it stops with the old store in place, and a new
    /// build of the app gets its own tries.
    @Test func aMigrationThatLosesARecordIsRolledBack() async throws {
        let (store, before) = try await Self.seededStore("losing")
        let losing = MigrationCoordinator<LosingPlanV3>(location: store.location)
        for launch in 1...4 {
            guard case .problem(.updateFailed) = losing.open() else {
                Issue.record("Launch \(launch) should have failed the update")
                return
            }
        }
        // Three tries after the first, then it stops with the snapshot back in place.
        #expect(try losing.readJournal()?.attempts == 3)
        #expect(losing.storedVersion() == 2)
        #expect(try StoreSQLite.manifest(of: store.location.storeURL) == before)

        // A new build, with the bug fixed.
        var fixed = MigrationCoordinator<LightweightPlanV3>(location: store.location)
        fixed.build = "next"
        guard case .ready(let container, let report) = fixed.open() else {
            Issue.record("The fixed build didn't open the store")
            return
        }
        #expect(report.snapshotRestored)
        #expect(MigrationCoordinator<LightweightPlanV3>.verify(container, against: before).isEmpty)
        try await Self.expectDemoIntact(in: container)
    }

    /// The snapshot and journal go seven days after a verified migration, not before.
    @Test func theSnapshotGoesAfterSevenDays() async throws {
        let (store, _) = try await Self.seededStore("cleanup")
        var coordinator = MigrationCoordinator<LightweightPlanV3>(location: store.location)
        coordinator.now = { TestTime.now }
        guard case .ready = coordinator.open() else {
            Issue.record("The store didn't open")
            return
        }
        #expect(FileManager.default.fileExists(atPath: store.location.recoveryDirectory.path))

        coordinator.now = { TestTime.day(6) }
        _ = coordinator.open()
        #expect(FileManager.default.fileExists(atPath: store.location.recoveryDirectory.path))

        coordinator.now = { TestTime.day(7) }
        _ = coordinator.open()
        #expect(!FileManager.default.fileExists(atPath: store.location.recoveryDirectory.path))
        #expect(try coordinator.readJournal() == nil)
    }

    /// Delete my data deletes the safety copy of a verified migration at once (0004 §1), and
    /// leaves one the next launch still needs.
    @Test func deleteMyDataDeletesTheSafetyCopy() async throws {
        let (store, _) = try await Self.seededStore("safety")
        guard case .ready = MigrationCoordinator<LightweightPlanV3>(location: store.location).open() else {
            Issue.record("The store didn't open")
            return
        }
        #expect(FileManager.default.fileExists(atPath: store.location.recoveryDirectory.path))
        try await StoreSafetyCopies(location: store.location).eraseAll()
        #expect(!FileManager.default.fileExists(atPath: store.location.recoveryDirectory.path))
        #expect(try MigrationCoordinator<LightweightPlanV3>(location: store.location).readJournal() == nil)
    }

    @Test func aSafetyCopyStillNeededIsKept() async throws {
        let (store, _) = try await Self.seededStore("needed")
        let losing = MigrationCoordinator<LosingPlanV3>(location: store.location)
        guard case .problem(.updateFailed) = losing.open() else {
            Issue.record("The update should have failed")
            return
        }
        try await StoreSafetyCopies(location: store.location).eraseAll()
        #expect(FileManager.default.fileExists(atPath: store.location.snapshotURL.path))
        #expect(try losing.readJournal()?.step == .migrated)
    }
}
