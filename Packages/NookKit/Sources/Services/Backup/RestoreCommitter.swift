import Foundation
import Models
import SwiftData

/// A restore's progress, written before each step, next to the store (0004 section 4).
struct RestoreJournal: Codable, Equatable, Sendable {
    enum Step: String, Codable, Sendable {
        case staged
        case safetyCopyTaken
        case writing
        case verified
        /// Undo restore is putting the safety copy back.
        case undoing
    }

    var step: Step
    var replacesEverything: Bool
    /// `kind/key` to the SHA-256 of each payload the restore writes.
    var expected: [String: String]
    var startedAt: Date
    var verifiedAt: Date?
}

/// The second half of Restore: a safety copy, then every record in one save, then a check.
///
/// The records go in with one `ModelContext` save, which is one SQLite transaction, so the store
/// holds either the old closet or the whole restored one, never a mix. Photo files go in before
/// the records that point to them; Replace removes the old ones only after the check. The journal
/// lets the next launch finish or tidy up after a kill at any step (`resume`), and the safety copy
/// gives Undo restore for 7 days.
struct RestoreCommitter {
    let container: ModelContainer
    let location: BackupLocation
    var now: @Sendable () -> Date = { .now }
    /// Free space for tests. `nil` reads the volume.
    var freeSpace: (@Sendable () -> Int64)?
    static let keepDays: Double = 7

    // MARK: Restoring

    func restore(_ copy: StagedCopy, as mode: RestoreMode) throws(BackupError) -> RestoreOutcome {
        do {
            return try PhotoFolderLock.run { try restoreThrowing(copy, as: mode) }
        } catch {
            // Nothing was written, or the save rolled back: the old closet is in place.
            if (try? readJournal())?.step != .verified { discard() }
            throw (error as? BackupError) ?? .failed
        }
    }

    /// `restore`, letting a test's simulated kill through with no tidying up.
    func restoreThrowing(_ copy: StagedCopy, as mode: RestoreMode) throws -> RestoreOutcome {
        let plan = RestorePlan.make(copy: copy.rows, phone: try rows(), mode: mode, now: now())
        var journal = RestoreJournal(
            step: .staged, replacesEverything: plan.replacesEverything, expected: plan.expected, startedAt: now())
        try checkSpace()
        try writeJournal(journal)
        try StoreCheckpoint.hit("restore.staged")
        try takeSafetyCopy()
        journal.step = .safetyCopyTaken
        try writeJournal(journal)
        try StoreCheckpoint.hit("restore.safetyCopyTaken")
        try movePhotos(from: copy)
        try StoreCheckpoint.hit("restore.photosMoved")
        journal.step = .writing
        try writeJournal(journal)
        try StoreCheckpoint.hit("restore.writing")
        try commit(plan.rows, replacesEverything: plan.replacesEverything)
        try StoreCheckpoint.hit("restore.saved")
        guard verify(journal) else {
            // Can't happen with one save, but if it ever did: put the old closet back.
            try undoThrowing()
            throw BackupError.failed
        }
        journal.step = .verified
        journal.verifiedAt = now()
        try writeJournal(journal)
        try StoreCheckpoint.hit("restore.verified")
        finish(journal)
        BackupLocation.remove(copy.folder)
        return RestoreOutcome(
            counts: BackupContents(try rows()).counts, added: plan.added, conflicts: plan.conflicts,
            deletedForGood: plan.deletedForGood, undoUntil: undoAvailable()?.until)
    }

    // MARK: Launch and Undo

    /// At launch, with the store open and nothing reading it yet: finishes or tidies up a restore
    /// that was stopped, finishes an interrupted Undo, and drops the safety copy after 7 days.
    /// Staging and unsaved exports from an earlier launch are always cleared.
    func resume() {
        PhotoFolderLock.run { resumeNow() }
    }

    private func resumeNow() {
        BackupLocation.remove(location.staging)
        BackupLocation.remove(location.exports)
        guard var journal = try? readJournal() else {
            BackupLocation.remove(location.safetyCopy)
            return
        }
        switch journal.step {
        case .staged, .safetyCopyTaken:
            discard()
        case .writing:
            guard verify(journal) else { return discard() }
            journal.step = .verified
            journal.verifiedAt = now()
            try? writeJournal(journal)
            finish(journal)
        case .verified:
            if undoAvailable() == nil { discard() }
        case .undoing:
            try? undoThrowing()
        }
    }

    func undoAvailable() -> UndoRestore? {
        guard let journal = try? readJournal(), journal.step == .verified, let verifiedAt = journal.verifiedAt,
            FileManager.default.fileExists(atPath: location.safetyStore.path)
        else { return nil }
        let until = verifiedAt.addingTimeInterval(Self.keepDays * 86_400)
        return now() < until ? UndoRestore(takenAt: journal.startedAt, until: until) : nil
    }

    /// Puts back the closet from before the last restore: every record and photo as it was, apart
    /// from pieces deleted for good since, which stay deleted.
    func undo() throws(BackupError) {
        guard undoAvailable() != nil, var journal = try? readJournal() else { throw .nothingToRestore }
        do {
            journal.step = .undoing
            try writeJournal(journal)
            try PhotoFolderLock.run { try undoThrowing() }
        } catch {
            throw (error as? BackupError) ?? .failed
        }
    }

    func undoThrowing() throws {
        let markers = try rows().filter { $0.kind == RecordKind.deletion.rawValue }
        let deleted = Set(markers.map(\.key))
        let restored = RecordCodec.restoredKinds
        let before = try StoreSQLite.rows(of: location.safetyStore)
            .map { StoreRow(kind: $0.kind, key: $0.key, payloadVersion: $0.payloadVersion, payload: $0.payload) }
            .filter { restored.contains($0.kind) && $0.kind != RecordKind.deletion.rawValue }
            .filter { !($0.kind == RecordKind.garment.rawValue && deleted.contains($0.key)) }
            // The pictures that show a piece deleted for good since stay deleted too (Phase 22b).
            .filter { !RestorePlan.showsDeletedPiece($0, deleted: deleted) }
        try commit(before + markers, replacesEverything: true)
        try StoreCheckpoint.hit("undo.saved")
        BackupLocation.remove(location.photos)
        if FileManager.default.fileExists(atPath: location.safetyPhotos.path) {
            try FileManager.default.moveItem(at: location.safetyPhotos, to: location.photos)
        }
        discard()
    }

    /// Deletes the safety copy and the journal.
    func discard() {
        BackupLocation.remove(location.safetyCopy)
        BackupLocation.remove(location.restoreJournal)
    }

    // MARK: Steps

    func rows() throws -> [StoreRow] {
        try StoreRow.all(in: ModelContext(container))
    }

    private func checkSpace() throws {
        let store = location.store.storeFiles.reduce(Int64(0)) { $0 + BackupLocation.size(of: $1) }
        let needed = store + store / 5 + 20_000_000
        let available = freeSpace?() ?? BackupArchiveReader.volumeSpace(at: location.store.directory)
        guard needed <= available else { throw BackupError.notEnoughSpace(needed: needed) }
    }

    /// The store, copied consistently, and the photos, cloned (APFS makes a copy that takes no
    /// space until the originals change). Left out of device backups.
    private func takeSafetyCopy() throws {
        BackupLocation.remove(location.safetyCopy)
        try BackupLocation.prepare(location.safetyCopy)
        try MigrationCoordinator<NookMigrationPlan>.copyStore(
            from: location.store.storeURL, to: location.safetyStore)
        guard try StoreSQLite.integrityCheck(location.safetyStore) == "ok" else { throw BackupError.failed }
        if FileManager.default.fileExists(atPath: location.photos.path) {
            try FileManager.default.copyItem(at: location.photos, to: location.safetyPhotos)
        }
    }

    /// Staged photos the app doesn't have yet move into place. An image never changes, so one
    /// with the same ID is the same picture.
    private func movePhotos(from copy: StagedCopy) throws {
        let staged = copy.photos
        let photos = PhotoFiles(directory: location.photos)
        let ids = staged.ids()
        guard !ids.isEmpty else { return }
        try BackupLocation.prepare(location.photos, backedUp: true)
        for id in ids where !photos.exists(id) {
            guard let from = staged.url(for: id), let to = photos.url(for: id) else { continue }
            try FileManager.default.moveItem(at: from, to: to)
        }
    }

    /// Writes the rows in one save. With `replacesEverything`, every other row of the restored
    /// kinds goes in the same save.
    private func commit(_ rows: [StoreRow], replacesEverything: Bool) throws {
        let context = ModelContext(container)
        let restored = RecordCodec.restoredKinds
        let date = now()
        try saveChanges(in: context) {
            var existing: [String: StoredRecord] = [:]
            for record in try context.fetch(FetchDescriptor<StoredRecord>()) where restored.contains(record.kind) {
                existing["\(record.kind)/\(record.key)"] = record
            }
            // A changed record is deleted and inserted again rather than edited, so no other
            // context can be left holding its old value.
            for row in rows {
                if let record = existing.removeValue(forKey: row.id) { context.delete(record) }
                context.insert(
                    StoredRecord(
                        kind: row.kind, key: row.key, payloadVersion: row.payloadVersion, payload: row.payload,
                        savedAt: date))
            }
            if replacesEverything {
                for record in existing.values { context.delete(record) }
            }
        }
    }

    /// The store holds every row the journal expects, and with Replace nothing else of those kinds.
    private func verify(_ journal: RestoreJournal) -> Bool {
        guard let all = try? rows() else { return false }
        let restored = RecordCodec.restoredKinds
        var found: [String: String] = [:]
        for row in all where restored.contains(row.kind) { found[row.id] = BackupFormat.sha256(row.payload) }
        let matches = journal.expected.allSatisfy { found[$0.key] == $0.value }
        return matches && (!journal.replacesEverything || found.count == journal.expected.count)
    }

    /// After a verified Replace, the photos only the old closet used go (the safety copy keeps
    /// them for Undo).
    private func finish(_ journal: RestoreJournal) {
        guard journal.replacesEverything, let all = try? rows() else { return }
        PhotoFiles(directory: location.photos).removeAll(except: BackupContents(all).photoIDs)
    }

    func readJournal() throws -> RestoreJournal? {
        guard FileManager.default.fileExists(atPath: location.restoreJournal.path) else { return nil }
        return try JSONDecoder().decode(RestoreJournal.self, from: Data(contentsOf: location.restoreJournal))
    }

    private func writeJournal(_ journal: RestoreJournal) throws {
        try location.store.makeDirectory()
        try JSONEncoder().encode(journal).write(
            to: location.restoreJournal, options: [.atomic, .completeFileProtection])
    }
}
