import Foundation
import Models
import SwiftData

/// A copy that passed every check, unpacked in staging and read into rows, waiting to be
/// restored. Nothing in the app has changed.
struct StagedCopy: Sendable {
    let id: UUID
    let folder: URL
    let manifest: BackupManifest
    /// The copy's records, each checked as a save checks it, at the current payload version.
    let rows: [StoreRow]

    /// The staged photo files, by image ID.
    var photos: PhotoFiles { PhotoFiles(directory: folder.appending(path: "photos", directoryHint: .isDirectory)) }
}

/// Check a copy and the first half of Restore (0004 section 4): decrypts the copy into staging and
/// runs every check before anything is written. A `storeCopy` is opened through the migration
/// coordinator in staging, so an older store is migrated there first, the normal way.
struct RestoreChecker {
    let location: BackupLocation
    var reader = BackupArchiveReader()
    /// Opens a staged raw store, migrating it if it's older. Tests pass a plan with more versions.
    var openStore: @Sendable (StoreLocation) -> StoreOpening = {
        MigrationCoordinator<NookMigrationPlan>(location: $0).open()
    }

    func check(_ url: URL, passphrase: String) throws(BackupError) -> StagedCopy {
        let id = UUID()
        let folder = location.staging.appending(path: id.uuidString, directoryHint: .isDirectory)
        do {
            try BackupLocation.prepare(location.staging)
            try BackupLocation.prepare(folder)
        } catch {
            throw .failed
        }
        do throws(BackupError) {
            let manifest = try reader.extract(url, passphrase: passphrase, into: folder)
            let rows: [StoreRow]
            switch manifest.kind {
            case .records: rows = try records(in: folder, manifest: manifest)
            case .storeCopy: rows = try storeRecords(in: folder)
            }
            let copy = StagedCopy(id: id, folder: folder, manifest: manifest, rows: rows)
            guard copy.photos.ids().allSatisfy({ manifest.files[BackupFormat.photoPath($0)] != nil }) else {
                throw .damaged
            }
            return copy
        } catch {
            BackupLocation.remove(folder)
            throw error
        }
    }

    /// The preview of a staged copy against what's on the phone now.
    static func preview(of copy: StagedCopy, phone: [StoreRow]) -> BackupPreview {
        let inCopy = BackupContents(copy.rows)
        let onPhone = BackupContents(phone)
        let deleted = inCopy.deletedForGood.union(onPhone.deletedForGood)
        return BackupPreview(
            id: copy.id, createdAt: copy.manifest.createdAt, inCopy: inCopy.counts, onPhone: onPhone.counts,
            photos: copy.photos.ids().count, includesBodyData: inCopy.includesBodyData,
            includesTryOnPhoto: inCopy.includesTryOnPhoto,
            deletedForGood: inCopy.garmentIDs.intersection(deleted).count,
            missingReferences: inCopy.missingReferences(photosPresent: Set(copy.photos.ids())))
    }

    /// Reads every `records/<kind>.json`. A kind this app doesn't know, a value that doesn't
    /// decode or check, or counts that differ from the manifest's: the copy is damaged.
    private func records(in folder: URL, manifest: BackupManifest) throws(BackupError) -> [StoreRow] {
        guard manifest.payloadVersion <= RecordPayload.currentVersion else { throw .newerVersion }
        var rows: [StoreRow] = []
        for path in manifest.files.keys.sorted() where path.hasPrefix("records/") {
            let name = String(path.dropFirst("records/".count))
            guard name.hasSuffix(".json"), let codec = RecordCodec.byKind[String(name.dropLast(5))] else {
                throw .damaged
            }
            do {
                rows += try codec.rows(Data(contentsOf: folder.appending(path: path)), manifest.payloadVersion)
            } catch {
                throw (error as? BackupError) ?? .damaged
            }
        }
        guard BackupContents(rows).counts == manifest.counts else { throw .damaged }
        return rows
    }

    /// Opens a raw store copy in staging through the migration coordinator, then checks every
    /// record through its value type, as a records copy is checked.
    private func storeRecords(in folder: URL) throws(BackupError) -> [StoreRow] {
        let store = StoreLocation(directory: folder.appending(path: "store", directoryHint: .isDirectory))
        let raw: [StoreRow]
        switch openStore(store) {
        case .ready(let container, _):
            do {
                raw = try StoreRow.all(in: ModelContext(container))
            } catch {
                throw .damaged
            }
        case .problem(.newerVersion): throw .newerVersion
        case .problem: throw .damaged
        }
        return try Self.checked(raw)
    }

    /// Every row through its kind's file and back, so each value decodes and checks. Kinds no
    /// export carries (the `UserDefaults` move marker) are left out.
    static func checked(_ rows: [StoreRow]) throws(BackupError) -> [StoreRow] {
        var checked: [StoreRow] = []
        for (kind, kindRows) in Dictionary(grouping: rows, by: \.kind) {
            guard let codec = RecordCodec.byKind[kind] else { continue }
            do {
                checked += try codec.rows(codec.file(kindRows), RecordPayload.currentVersion)
            } catch {
                throw (error as? BackupError) ?? .damaged
            }
        }
        return checked
    }
}
