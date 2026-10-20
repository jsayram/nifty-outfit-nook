import CoreData
import Foundation
import SQLite3
import SwiftData

// Phase 20a persistence spike: PRD 11.7's migration rules around SwiftData's own migration.
//
// SwiftData migrates a store when a container opens it, and a custom stage saves more than once
// (`didMigrate` here saves every 200 records). A crash in between leaves a store whose schema is
// already the new version but whose data isn't finished, and the next launch would open it as if
// it were done. So the coordinator wraps the whole thing:
//
// 1. Work out the store's version from its metadata. A version this build doesn't know (a newer
//    app's store, or a damaged file) opens the recovery path and is never migrated or reset.
// 2. Check free space, journal "snapshotting", copy the store to a recovery snapshot, check the
//    snapshot's integrity and record a manifest (IDs, counts and image hashes) in the journal.
// 3. Journal "migrating", let SwiftData migrate, journal "migrated".
// 4. Verify the migrated store against the manifest, then journal "verified".
// 5. On the next launch, any journal short of "verified" puts the snapshot back and starts again;
//    after three tries it stops and opens the recovery path with the snapshot kept.
// 6. Seven days after a verified upgrade, the snapshot and journal are deleted.

/// What the store had before a migration: enough to prove nothing was lost or changed.
struct SpikeManifest: Codable, Equatable, Sendable {
    var garmentIDs: [String]
    var lookIDs: [String]
    var suitcaseIDs: [String]
    /// Each garment with a stored photo, by ID, with its file's hash. Empty when the file was
    /// already missing before the migration.
    var photoHashes: [String: String]
}

struct SpikeMigrationJournal: Codable, Equatable, Sendable {
    enum Step: String, Codable, Sendable {
        case snapshotting
        case snapshotTaken
        case migrating
        case migrated
        case verified
    }

    var from: Int
    var to: Int
    var step: Step
    var manifest: SpikeManifest?
    var attempts: Int
    var verifiedAt: Date?
}

/// The store versions this build knows.
enum SpikeStoreVersion: Int, CaseIterable, Sendable {
    case v1 = 1
    case v2 = 2
    case v3 = 3

    static let current = SpikeStoreVersion.v3

    var schema: Schema {
        switch self {
        case .v1: Schema(versionedSchema: SpikeSchemaV1.self)
        case .v2: Schema(versionedSchema: SpikeSchemaV2.self)
        case .v3: Schema(versionedSchema: SpikeSchemaV3.self)
        }
    }
}

enum SpikeRecoveryReason: Equatable, Sendable {
    /// The store's schema isn't one this build knows: a newer app's store, or not a store.
    case unsupportedSchema
    case notEnoughSpace(needed: Int64, available: Int64)
    /// The migrated store didn't match the manifest; the snapshot was put back.
    case verificationFailed([String])
    /// Migration failed three times in a row; the snapshot was put back and kept.
    case migrationKeepsFailing
}

enum SpikeOpenOutcome {
    case ready(ModelContainer, SpikeOpenReport)
    /// The closet isn't opened. The old store (or the snapshot) is kept for export.
    case recovery(SpikeRecoveryReason)
}

struct SpikeOpenReport: Equatable, Sendable {
    var migratedFrom: SpikeStoreVersion?
    /// What the journal said at launch, if a migration had been interrupted.
    var resumedAfter: SpikeMigrationJournal.Step?
    var snapshotRestored = false
}

struct SpikeMigrationCoordinator: Sendable {
    let location: SpikeStoreLocation
    var now: @Sendable () -> Date = { .now }
    /// Free space the coordinator believes there is, for tests. `nil` reads the volume.
    var availableSpace: (@Sendable () -> Int64)?
    var maximumAttempts = 3
    static let snapshotKeepDays: Double = 7

    // MARK: Opening

    func open() throws -> SpikeOpenOutcome {
        var report = SpikeOpenReport()
        if var journal = try readJournal() {
            report.resumedAfter = journal.step
            switch journal.step {
            case .snapshotting:
                // The live store wasn't touched yet. Throw the half-made snapshot away.
                try discardSnapshot()
                try removeJournal()
            case .snapshotTaken, .migrating, .migrated:
                // The live store may be half migrated. Put the verified snapshot back.
                try restoreSnapshot()
                report.snapshotRestored = true
                journal.attempts += 1
                journal.step = .snapshotTaken
                if journal.attempts >= maximumAttempts {
                    try writeJournal(journal)
                    return .recovery(.migrationKeepsFailing)
                }
                try writeJournal(journal)
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
        guard let version = try storedVersion() else { return .recovery(.unsupportedSchema) }
        if version == .current {
            return .ready(try container(), report)
        }
        return try migrate(from: version, report: report)
    }

    /// The store's version from its metadata, without opening it. `nil` for a version this build
    /// doesn't know or a file that isn't a store.
    func storedVersion() throws -> SpikeStoreVersion? {
        let metadata: [String: Any]
        do {
            metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                type: .sqlite, at: location.storeURL)
        } catch {
            return nil
        }
        return SpikeStoreVersion.allCases.last { version in
            NSManagedObjectModel.makeManagedObjectModel(for: version.schema)?
                .isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) ?? false
        }
    }

    func container() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        return try ModelContainer(
            for: SpikeStoreVersion.current.schema, migrationPlan: SpikeMigrationPlan.self,
            configurations: [ModelConfiguration(url: location.storeURL)])
    }

    // MARK: Migrating

    private func migrate(from version: SpikeStoreVersion, report: SpikeOpenReport) throws -> SpikeOpenOutcome {
        var report = report
        report.migratedFrom = version
        var journal = try readJournal()
        if journal?.step != .snapshotTaken {
            let needed = try storeSize() * 2 + 20_000_000
            let available = availableSpace?() ?? volumeSpace()
            guard available >= needed else { return .recovery(.notEnoughSpace(needed: needed, available: available)) }

            journal = SpikeMigrationJournal(
                from: version.rawValue, to: SpikeStoreVersion.current.rawValue, step: .snapshotting, attempts: 0)
            try writeJournal(journal!)
            try SpikeCheckpoint.hit("journal.snapshotting")
            try takeSnapshot()
            try SpikeCheckpoint.hit("snapshot.copied")
            journal!.manifest = try SpikeSQLite.manifest(of: location.snapshotURL, images: location.imagesDirectory)
            journal!.step = .snapshotTaken
            try writeJournal(journal!)
            try SpikeCheckpoint.hit("journal.snapshotTaken")
        }
        guard var journal, let manifest = journal.manifest else { return .recovery(.migrationKeepsFailing) }

        journal.step = .migrating
        try writeJournal(journal)
        try SpikeCheckpoint.hit("journal.migrating")
        var migrated: ModelContainer? = try container()
        try SpikeCheckpoint.hit("migration.finished")
        journal.step = .migrated
        try writeJournal(journal)
        try SpikeCheckpoint.hit("journal.migrated")

        let problems = try Self.verify(migrated!, against: manifest)
        guard problems.isEmpty else {
            migrated = nil
            try restoreSnapshot()
            return .recovery(.verificationFailed(problems))
        }
        try SpikeCheckpoint.hit("verified")
        journal.step = .verified
        journal.verifiedAt = now()
        try writeJournal(journal)
        try SpikeCheckpoint.hit("journal.verified")
        return .ready(migrated!, report)
    }

    /// Everything that differs between a migrated store and the manifest taken before it.
    static func verify(_ container: ModelContainer, against manifest: SpikeManifest) throws -> [String] {
        let context = ModelContext(container)
        var problems: [String] = []
        let garments = try context.fetch(FetchDescriptor<SpikeSchemaV3.GarmentRecord>())
        let looks = try context.fetch(FetchDescriptor<LookRecord>())
        let suitcases = try context.fetch(FetchDescriptor<SuitcaseRecord>())
        let assets = try context.fetchCount(FetchDescriptor<SpikeSchemaV3.ImageAssetRecord>())
        if garments.map(\.garmentID).sorted() != manifest.garmentIDs { problems.append("garment IDs differ") }
        if looks.map(\.lookID).sorted() != manifest.lookIDs { problems.append("look IDs differ") }
        if suitcases.map(\.suitcaseID).sorted() != manifest.suitcaseIDs { problems.append("suitcase IDs differ") }
        if assets != manifest.photoHashes.count {
            problems.append("\(assets) image records for \(manifest.photoHashes.count) photos")
        }
        for garment in garments {
            guard let expected = manifest.photoHashes[garment.garmentID] else {
                if !garment.images.isEmpty { problems.append("\(garment.garmentID) has images but no photo") }
                continue
            }
            guard garment.images.count == 1, let image = garment.images.first else {
                problems.append("\(garment.garmentID) has \(garment.images.count) image records")
                continue
            }
            let matches = expected.isEmpty ? image.state == "missing" : image.sha256 == expected
            if !matches { problems.append("\(garment.garmentID) image hash differs") }
        }
        return problems
    }

    // MARK: Snapshot and journal

    private func takeSnapshot() throws {
        try discardSnapshot()
        try FileManager.default.createDirectory(at: location.recoveryDirectory, withIntermediateDirectories: true)
        try Self.copyStore(from: location.storeURL, to: location.snapshotURL)
        let integrity = try SpikeSQLite.integrityCheck(location.snapshotURL)
        guard integrity == "ok" else { throw SpikeStoreFailure.snapshotDamaged(integrity) }
    }

    func restoreSnapshot() throws {
        try Self.copyStore(from: location.snapshotURL, to: location.storeURL)
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

    func readJournal() throws -> SpikeMigrationJournal? {
        guard FileManager.default.fileExists(atPath: location.journalURL.path) else { return nil }
        return try JSONDecoder().decode(SpikeMigrationJournal.self, from: Data(contentsOf: location.journalURL))
    }

    private func writeJournal(_ journal: SpikeMigrationJournal) throws {
        #if os(iOS)
            try JSONEncoder().encode(journal).write(to: location.journalURL, options: [.atomic, .completeFileProtection])
        #else
            try JSONEncoder().encode(journal).write(to: location.journalURL, options: [.atomic])
        #endif
    }

    private func removeJournal() throws {
        if FileManager.default.fileExists(atPath: location.journalURL.path) {
            try FileManager.default.removeItem(at: location.journalURL)
        }
    }

    private func storeSize() throws -> Int64 {
        let names = ["", "-wal", "-shm"].map { location.storeURL.path + $0 }
        return try names.reduce(Int64(0)) { total, path in
            guard FileManager.default.fileExists(atPath: path) else { return total }
            let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 ?? 0
            return total + size
        }
    }

    private func volumeSpace() -> Int64 {
        let values = try? location.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

enum SpikeStoreFailure: Error, Equatable {
    case snapshotDamaged(String)
    case sqlite(String)
}

/// Read-only SQLite access for checks that must not depend on the schema version: integrity and
/// the manifest. Core Data names tables `Z<ENTITY>` and columns `Z<ATTRIBUTE>`.
enum SpikeSQLite {
    static func integrityCheck(_ url: URL) throws -> String {
        try rows(in: url, "PRAGMA integrity_check").first?.first.flatMap { $0 } ?? "no result"
    }

    static func manifest(of storeURL: URL, images directory: URL) throws -> SpikeManifest {
        let images = SpikeImageFiles(directory: directory)
        let garments = try rows(in: storeURL, "SELECT ZGARMENTID, ZPHOTOREF FROM ZGARMENTRECORD")
        var hashes: [String: String] = [:]
        for row in garments {
            guard let photoID = SpikePhotoRef.storedID(row[1]) else { continue }
            hashes[row[0] ?? ""] = try images.describe(SpikeImageFiles.fileName(forPhoto: photoID))?.sha256 ?? ""
        }
        return SpikeManifest(
            garmentIDs: garments.compactMap { $0[0] }.sorted(),
            lookIDs: try rows(in: storeURL, "SELECT ZLOOKID FROM ZLOOKRECORD").compactMap { $0[0] }.sorted(),
            suitcaseIDs: try rows(in: storeURL, "SELECT ZSUITCASEID FROM ZSUITCASERECORD").compactMap { $0[0] }.sorted(),
            photoHashes: hashes)
    }

    static func rows(in url: URL, _ sql: String) throws -> [[String?]] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw SpikeStoreFailure.sqlite("open \(url.lastPathComponent)")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SpikeStoreFailure.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let columns = sqlite3_column_count(statement)
            result.append(
                (0..<columns).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                })
        }
        return result
    }
}
