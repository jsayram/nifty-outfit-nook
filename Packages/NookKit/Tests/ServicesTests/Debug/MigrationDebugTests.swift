#if DEBUG
    import Foundation
    import Models
    import SwiftData
    import Testing

    @testable import Services

    /// The device-check helpers for migrations (debug builds only): `-make-old-store` really makes a
    /// version 1 store of the same records, which the real migration then upgrades, and the pause
    /// and kill hooks sit on the checkpoints the crash tests use. (The kill itself ends the
    /// process, so it's checked by hand on the simulator and the device.)
    struct MigrationDebugTests {
        /// The 21b store (version 1, 50 records), copied into a test store folder.
        private static func version1Store(_ label: String) throws -> TemporaryStore {
            let store = try TemporaryStore(label)
            try store.location.makeDirectory()
            try FileManager.default.copyItem(
                at: try Phase21bFixtures.url("Nook-v1", "store"), to: store.location.storeURL)
            return store
        }

        /// Migrates the store to version 2 and lets the container go.
        private static func migrate(_ store: TemporaryStore) throws {
            let coordinator = MigrationCoordinator<NookMigrationPlan>(location: store.location)
            guard case .ready = coordinator.open() else {
                Issue.record("The store didn't open")
                return
            }
        }

        @Test func aVersion2StoreBecomesAVersion1StoreWithTheSameRecords() throws {
            let store = try Self.version1Store("old-store")
            try Self.migrate(store)
            let coordinator = MigrationCoordinator<NookMigrationPlan>(location: store.location)
            #expect(coordinator.storedVersion() == 2)
            let manifest = try StoreSQLite.manifest(of: store.location.storeURL)
            let dates = try StoreSQLite.rowsWithDates(of: store.location.storeURL).reduce(into: [String: Date]()) {
                $0["\($1.kind)/\($1.key)"] = $1.savedAt
            }

            #expect(MigrationDebug.makeOldStore(at: store.location) == .written(records: 50))

            #expect(coordinator.storedVersion() == 1)
            #expect(try StoreSQLite.manifest(of: store.location.storeURL) == manifest)
            #expect(try StoreSQLite.integrityCheck(store.location.storeURL) == "ok")
            let after = try StoreSQLite.rowsWithDates(of: store.location.storeURL)
            #expect(after.count == 50)
            for row in after {
                let before = try #require(dates["\(row.kind)/\(row.key)"])
                #expect(abs(row.savedAt.timeIntervalSince(before)) < 0.001)
            }
            #expect(
                !FileManager.default.fileExists(atPath: store.location.directory.appending(path: "Nook-old.store").path)
            )

            // The next launch runs the real migration, and every record comes through.
            guard case .ready(let container, let report) = coordinator.open() else {
                Issue.record("The old store didn't migrate")
                return
            }
            #expect(report.migratedFrom == 1)
            #expect(coordinator.storedVersion() == 2)
            #expect(Set(try StoreRow.all(in: ModelContext(container))) == Set(try Phase21bFixtures.rows()))
        }

        @Test func aStoreThatIsAlreadyVersion1IsLeftAlone() throws {
            let store = try Self.version1Store("already-old")
            let before = try StoreSQLite.manifest(of: store.location.storeURL)
            #expect(MigrationDebug.makeOldStore(at: store.location) == .alreadyOld)
            #expect(try StoreSQLite.manifest(of: store.location.storeURL) == before)
        }

        @Test func noStoreIsReported() throws {
            let store = try TemporaryStore("no-store")
            #expect(MigrationDebug.makeOldStore(at: store.location) == .noStore)
        }

        @Test func anUnfinishedMigrationIsNotCovered() throws {
            let store = try Self.version1Store("pending")
            try Self.migrate(store)
            let journal = MigrationJournal(
                from: 1, to: 2, step: .migrating, manifest: nil, attempts: 0, build: nil, verifiedAt: nil)
            try JSONEncoder().encode(journal).write(to: store.location.journalURL)
            #expect(MigrationDebug.makeOldStore(at: store.location) == .migrationPending)
            #expect(MigrationCoordinator<NookMigrationPlan>(location: store.location).storedVersion() == 2)
        }

        @Test func theStoreLinesShowTheRecordsTheJournalAndTheIntegrityCheck() throws {
            let store = try Self.version1Store("last-open")
            try Self.migrate(store)
            let lines = MigrationDebug.storeLines(location: store.location)
            #expect(lines.contains { $0.hasPrefix("Records: 50") })
            #expect(lines.contains { $0.hasPrefix("Journal: step verified, version 1 to 2") })
            #expect(lines.contains { $0.hasPrefix("Integrity check: ok") })
        }

        @Test func aPauseWaitsAtTheNamedStepOnly() {
            MigrationDebug.install(arguments: ["-migration-pause-at", "test.pause", "0.3"])
            defer { MigrationDebug.install(arguments: []) }
            let clock = ContinuousClock()
            let other = clock.measure { MigrationDebug.reached("test.other") }
            let paused = clock.measure { MigrationDebug.reached("test.pause") }
            #expect(other < .milliseconds(200))
            #expect(paused >= .milliseconds(300))
        }
    }
#endif
