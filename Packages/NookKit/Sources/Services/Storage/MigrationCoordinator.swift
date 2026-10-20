import CoreData
import CryptoKit
import Foundation
import Models
import SQLite3
import SwiftData

// Opening the store, with PRD 11.7's migration rules around SwiftData's own migration (Phase 21a,
// promoted from the Phase 20a spike: docs/decisions/0003-persistence-spike.md).
//
// SwiftData migrates a store when a container opens it, and a custom stage can save more than
// once. A crash in between leaves a store already marked as the new version with only part of
// its data migrated, and the next launch would open it as if it were done. So every migration
// goes through these steps, each written to a journal next to the store first:
//
// 1. Read the store's version from its metadata, without opening it. A version this build
//    doesn't know (a newer app's store, or a damaged file) is never migrated or reset: the app
//    shows the problem and leaves the file alone.
// 2. Check there's room, journal `snapshotting`, copy the store to a recovery snapshot (left out
//    of device backups), check the copy's integrity, and record a manifest of every record (its
//    kind, key and a hash of its payload) in the journal: `snapshotTaken`.
// 3. Journal `migrating`, let SwiftData migrate, journal `migrated`.
// 4. Check the migrated store against the manifest, then journal `verified`. If they differ, the
//    journal stays short of `verified` and the next launch puts the snapshot back.
// 5. At the next launch, before any container exists (20a: restoring with one open failed with
//    SQLITE_BUSY), any journal short of `verified` puts the snapshot back and tries again. After
//    three tries it stops, keeps the snapshot and shows the problem.
// 6. Seven days after a verified migration, the snapshot and the journal are deleted.
//
// Nothing here logs anything: the journal holds record kinds, keys (IDs) and hashes, never
// content, and errors are reported as a `StoreProblem` with no detail.

/// Why the store couldn't be opened. The app shows a recovery screen; nothing is reset.
public enum StoreProblem: Hashable, Sendable {
    /// The store was saved by a newer version of the app, or isn't a store this build can read.
    case newerVersion
    /// Not enough free space to take the safety copy a migration needs.
    case notEnoughSpace
    /// The migration failed, or its result didn't match the store before it. The store from
    /// before is back in place (or will be at the next launch), and kept.
    case updateFailed
    /// The store couldn't be opened at all.
    case couldNotOpen
}

/// What happened while opening, for tests and the checkpoint.
public struct StoreOpenReport: Hashable, Sendable {
    /// The version the store was migrated from, if it was.
    public var migratedFrom: Int?
    /// What the journal said at launch, if a migration had been interrupted.
    public var resumedAfter: MigrationJournal.Step?
    /// The snapshot was put back before opening.
    public var snapshotRestored = false
}

/// The result of opening the store.
public enum StoreOpening {
    case ready(ModelContainer, StoreOpenReport)
    case problem(StoreProblem)
}

/// What the store held before a migration: every record's kind and key with a hash of its
/// payload. Enough to prove nothing was lost or changed. No content.
public struct StoreManifest: Codable, Hashable, Sendable {
    /// `kind/key` to the SHA-256 of the payload, in hex.
    public var records: [String: String]
}

/// The migration's progress, written before each step.
public struct MigrationJournal: Codable, Hashable, Sendable {
    public enum Step: String, Codable, Sendable {
        case snapshotting
        case snapshotTaken
        case migrating
        case migrated
        case verified
    }

    public var from: Int
    public var to: Int
    public var step: Step
    public var manifest: StoreManifest?
    /// Tries after the first that were interrupted or failed.
    public var attempts: Int
    /// The app build that made the tries.
    public var build: String?
    public var verifiedAt: Date?
}

/// Opens the store at a location, migrating it safely through `Plan`'s versions.
public struct MigrationCoordinator<Plan: SchemaMigrationPlan>: Sendable {
    public let location: StoreLocation
    var now: @Sendable () -> Date = { .now }
    /// Free space for tests. `nil` reads the volume.
    var availableSpace: (@Sendable () -> Int64)?
    var maximumAttempts = 3
    /// The app's build number, kept in the journal so a new build gets fresh tries.
    var build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    static var snapshotKeepDays: Double { 7 }

    public init(location: StoreLocation) {
        self.location = location
    }

    /// The version the app writes: the last one in the plan, counted from 1.
    public static var currentVersion: Int { Plan.schemas.count }

    // MARK: Opening

    /// Opens the store, migrating it first if it's an older version. Never deletes or resets a
    /// store it can't open.
    public func open() -> StoreOpening {
        do {
            return try openThrowing()
        } catch {
            return .problem(.couldNotOpen)
        }
    }

    /// `open()`, letting a test's simulated kill through.
    func openThrowing() throws -> StoreOpening {
        try location.makeDirectory()
        var report = StoreOpenReport()
        if var journal = try readJournal() {
            report.resumedAfter = journal.step
            switch journal.step {
            case .snapshotting:
                // The store wasn't touched yet. Throw the half-made snapshot away.
                try discardSnapshot()
                try removeJournal()
            case .snapshotTaken, .migrating, .migrated:
                // The store may be half migrated, or failed its check. Put the snapshot back.
                try restoreSnapshot()
                report.snapshotRestored = true
                // A new build of the app gets three tries of its own.
                journal.attempts = journal.build == build ? journal.attempts + 1 : 0
                journal.build = build
                journal.step = .snapshotTaken
                try writeJournal(journal)
                if journal.attempts >= maximumAttempts { return .problem(.updateFailed) }
            case .verified:
                if let verifiedAt = journal.verifiedAt,
                    now().timeIntervalSince(verifiedAt) >= Self.snapshotKeepDays * 86_400
                {
                    try discardSnapshot()
                    try removeJournal()
                }
            }
        }

        guard FileManager.default.fileExists(atPath: location.storeURL.path) else {
            return .ready(try container(), report)
        }
        guard let version = storedVersion() else { return .problem(.newerVersion) }
        if version == Self.currentVersion {
            return .ready(try container(), report)
        }
        return try migrate(from: version, report: report)
    }

    /// The store's version from its metadata, counted from 1, without opening it. `nil` for a
    /// version this build doesn't know, or a file that isn't a store.
    public func storedVersion() -> Int? {
        guard
            let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
                type: .sqlite, at: location.storeURL)
        else { return nil }
        let index = Plan.schemas.lastIndex { schema in
            NSManagedObjectModel.makeManagedObjectModel(for: Schema(versionedSchema: schema))?
                .isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) ?? false
        }
        return index.map { $0 + 1 }
    }

    /// A container on the store at the current version. Never syncs with CloudKit: sync will be
    /// `CKSyncEngine`'s, never SwiftData's own mirroring (20a).
    func container() throws -> ModelContainer {
        guard let current = Plan.schemas.last else { throw CoordinatorFailure.noSchema }
        let container = try ModelContainer(
            for: Schema(versionedSchema: current), migrationPlan: Plan.self,
            configurations: [ModelConfiguration(url: location.storeURL, cloudKitDatabase: .none)])
        location.protectStoreFiles()
        return container
    }

    // MARK: Migrating

    private func migrate(from version: Int, report: StoreOpenReport) throws -> StoreOpening {
        var report = report
        report.migratedFrom = version
        var resumed = try readJournal()
        if resumed?.step != .snapshotTaken {
            let needed = storeSize() * 2 + 20_000_000
            let available = availableSpace?() ?? volumeSpace()
            guard available >= needed else { return .problem(.notEnoughSpace) }

            var fresh = MigrationJournal(
                from: version, to: Self.currentVersion, step: .snapshotting, attempts: 0, build: build)
            try writeJournal(fresh)
            try StoreCheckpoint.hit("journal.snapshotting")
            try takeSnapshot()
            try StoreCheckpoint.hit("snapshot.copied")
            fresh.manifest = try StoreSQLite.manifest(of: location.snapshotURL)
            fresh.step = .snapshotTaken
            try writeJournal(fresh)
            try StoreCheckpoint.hit("journal.snapshotTaken")
            resumed = fresh
        }
        guard var journal = resumed, let manifest = journal.manifest else { return .problem(.updateFailed) }

        journal.step = .migrating
        try writeJournal(journal)
        try StoreCheckpoint.hit("journal.migrating")
        let migrated: ModelContainer
        do {
            migrated = try container()
        } catch let kill as StoreCheckpoint.Kill {
            throw kill
        } catch {
            // The journal says `migrating`, so the next launch puts the snapshot back.
            return .problem(.updateFailed)
        }
        try StoreCheckpoint.hit("migration.finished")
        journal.step = .migrated
        try writeJournal(journal)
        try StoreCheckpoint.hit("journal.migrated")

        guard Self.verify(migrated, against: manifest).isEmpty else {
            // The journal stays at `migrated`: the next launch puts the snapshot back before it
            // opens anything, and tries again.
            return .problem(.updateFailed)
        }
        try StoreCheckpoint.hit("verified")
        journal.step = .verified
        journal.verifiedAt = now()
        try writeJournal(journal)
        try StoreCheckpoint.hit("journal.verified")
        return .ready(migrated, report)
    }

    /// Every way the migrated store differs from the manifest taken before it: records missing,
    /// added or changed. A migration that's meant to change payloads must say how here.
    static func verify(_ container: ModelContainer, against manifest: StoreManifest) -> [String] {
        guard let records = try? ModelContext(container).fetch(FetchDescriptor<StoredRecord>()) else {
            return ["the migrated store couldn't be read"]
        }
        var after: [String: String] = [:]
        for record in records {
            after["\(record.kind)/\(record.key)"] = StoreSQLite.hash(record.payload)
        }
        var problems: [String] = []
        let missing = Set(manifest.records.keys).subtracting(after.keys)
        let added = Set(after.keys).subtracting(manifest.records.keys)
        let changed = manifest.records.filter { key, hash in after[key].map { $0 != hash } ?? false }
        if !missing.isEmpty { problems.append("\(missing.count) records missing") }
        if !added.isEmpty { problems.append("\(added.count) records added") }
        if !changed.isEmpty { problems.append("\(changed.count) records changed") }
        return problems
    }

    // MARK: Snapshot and journal

    private func takeSnapshot() throws {
        try discardSnapshot()
        try StoreLocation.makeProtectedDirectory(location.recoveryDirectory)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var recovery = location.recoveryDirectory
        try recovery.setResourceValues(values)
        try Self.copyStore(from: location.storeURL, to: location.snapshotURL)
        guard try StoreSQLite.integrityCheck(location.snapshotURL) == "ok" else {
            throw CoordinatorFailure.snapshotDamaged
        }
    }

    /// Puts the snapshot back over the store. The app only calls it at launch, before any
    /// container is open. A container released a moment ago can still hold its SQLite connection
    /// (20a saw SQLITE_BUSY on CI when a test reopened in the same process), so a busy store is
    /// tried a few more times.
    private func restoreSnapshot() throws {
        guard FileManager.default.fileExists(atPath: location.snapshotURL.path) else {
            throw CoordinatorFailure.snapshotMissing
        }
        var attempt = 0
        while true {
            do {
                try Self.copyStore(from: location.snapshotURL, to: location.storeURL)
                return
            } catch let error as NSError where error.domain == NSSQLiteErrorDomain && error.code == 5 && attempt < 10 {
                attempt += 1
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }

    private func discardSnapshot() throws {
        if FileManager.default.fileExists(atPath: location.recoveryDirectory.path) {
            try FileManager.default.removeItem(at: location.recoveryDirectory)
        }
    }

    /// Copies a SQLite store with its write-ahead log through Core Data, which takes care of the
    /// `-wal` and `-shm` files and leaves a consistent copy.
    static func copyStore(from source: URL, to destination: URL) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try coordinator.replacePersistentStore(at: destination, withPersistentStoreFrom: source, type: .sqlite)
    }

    func readJournal() throws -> MigrationJournal? {
        guard FileManager.default.fileExists(atPath: location.journalURL.path) else { return nil }
        return try JSONDecoder().decode(MigrationJournal.self, from: Data(contentsOf: location.journalURL))
    }

    private func writeJournal(_ journal: MigrationJournal) throws {
        try JSONEncoder().encode(journal).write(to: location.journalURL, options: [.atomic, .completeFileProtection])
    }

    private func removeJournal() throws {
        if FileManager.default.fileExists(atPath: location.journalURL.path) {
            try FileManager.default.removeItem(at: location.journalURL)
        }
    }

    /// The store's size with its `-wal` and `-shm`, read with `fileSizeKey` (no file dates).
    private func storeSize() -> Int64 {
        location.storeFiles.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Free space for a file the app needs to write. `PrivacyInfo.xcprivacy` declares the disk
    /// space API with reason `E174.1`: the app checks there's room before writing, and doesn't
    /// start the migration if there isn't.
    private func volumeSpace() -> Int64 {
        let values = try? location.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    enum CoordinatorFailure: Error {
        case noSchema
        case snapshotDamaged
        case snapshotMissing
    }
}

extension StoreCheckpoint {
    /// What a test throws from the checkpoint handler, standing for the app being killed there.
    struct Kill: Error, Equatable {
        let checkpoint: String
    }
}

/// Read-only SQLite access for the checks that mustn't depend on the schema version: integrity
/// and the manifest. Core Data names the table `ZSTOREDRECORD` and its columns `Z<ATTRIBUTE>`.
enum StoreSQLite {
    static func integrityCheck(_ url: URL) throws -> String {
        var result = "no result"
        try query(url, "PRAGMA integrity_check") { statement in
            if let text = sqlite3_column_text(statement, 0) { result = String(cString: text) }
        }
        return result
    }

    static func manifest(of url: URL) throws -> StoreManifest {
        var records: [String: String] = [:]
        try query(url, "SELECT ZKIND, ZKEY, ZPAYLOAD FROM ZSTOREDRECORD") { statement in
            guard let kind = sqlite3_column_text(statement, 0), let key = sqlite3_column_text(statement, 1) else {
                return
            }
            let count = Int(sqlite3_column_bytes(statement, 2))
            let payload = sqlite3_column_blob(statement, 2).map { Data(bytes: $0, count: count) } ?? Data()
            records["\(String(cString: kind))/\(String(cString: key))"] = hash(payload)
        }
        return StoreManifest(records: records)
    }

    /// Moves everything in a closed store's write-ahead log into the store file itself and
    /// empties the log, so the one file is the whole store (Phase 21b: the recovery screen's
    /// store copy carries only that file).
    static func checkpoint(_ url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw SQLiteFailure.open
        }
        defer { sqlite3_close(database) }
        guard sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil) == SQLITE_OK,
            sqlite3_exec(database, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK
        else { throw SQLiteFailure.prepare }
    }

    /// Every row of a closed store file, as stored, for Undo restore (Phase 21b).
    static func rows(of url: URL) throws -> [(kind: String, key: String, payloadVersion: Int, payload: Data)] {
        var rows: [(kind: String, key: String, payloadVersion: Int, payload: Data)] = []
        try query(url, "SELECT ZKIND, ZKEY, ZPAYLOADVERSION, ZPAYLOAD FROM ZSTOREDRECORD") { statement in
            guard let kind = sqlite3_column_text(statement, 0), let key = sqlite3_column_text(statement, 1) else {
                return
            }
            let count = Int(sqlite3_column_bytes(statement, 3))
            let payload = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: count) } ?? Data()
            rows.append(
                (String(cString: kind), String(cString: key), Int(sqlite3_column_int64(statement, 2)), payload))
        }
        return rows
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func query(_ url: URL, _ sql: String, row: (OpaquePointer?) -> Void) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw SQLiteFailure.open
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw SQLiteFailure.prepare }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }

    enum SQLiteFailure: Error {
        case open
        case prepare
    }
}

/// The migration snapshot, for Delete my data: a copy of her data from before the last migration,
/// kept up to seven days (docs/decisions/0004-backup-and-recovery.md, section 1, says Delete my
/// data deletes safety copies at once). The app only runs once a migration is verified, so the
/// snapshot is never needed then. A journal short of `verified` is left alone, since the next
/// launch needs that snapshot to put the store back.
public struct StoreSafetyCopies: ErasableStore {
    let location: StoreLocation

    public init(location: StoreLocation) {
        self.location = location
    }

    public func eraseAll() async throws(StoreError) {
        let journalURL = location.journalURL
        if FileManager.default.fileExists(atPath: journalURL.path) {
            guard let data = try? Data(contentsOf: journalURL),
                let journal = try? JSONDecoder().decode(MigrationJournal.self, from: data), journal.step == .verified
            else { return }
        }
        do {
            if FileManager.default.fileExists(atPath: location.recoveryDirectory.path) {
                try FileManager.default.removeItem(at: location.recoveryDirectory)
            }
            if FileManager.default.fileExists(atPath: journalURL.path) {
                try FileManager.default.removeItem(at: journalURL)
            }
        } catch {
            throw .unavailable
        }
    }
}
