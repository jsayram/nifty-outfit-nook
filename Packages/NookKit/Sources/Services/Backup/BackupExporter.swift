import Foundation
import Models
import SwiftData

/// Makes the encrypted export (Phase 21b, 0004 section 3).
///
/// A `records` copy reads every row in one fetch, so the records agree with each other, and
/// hashes every photo they point to before writing anything, so the manifest can go first. Each
/// photo is hashed again as it's added; a photo that changed in between stops the export. The
/// archive is encrypted as it's written, into `exports`, and a partial file is deleted if
/// anything fails.
struct BackupExporter {
    let location: BackupLocation
    var now: @Sendable () -> Date = { .now }
    var calendar = Calendar.current
    /// Free space for tests. `nil` reads the volume.
    var freeSpace: (@Sendable () -> Int64)?
    static let spaceMargin: Int64 = 50_000_000

    /// What an export of these rows would hold.
    func summary(of rows: [StoreRow]) -> BackupSummary {
        let contents = BackupContents(rows)
        let photos = PhotoFiles(directory: location.photos)
        let present = contents.photoIDs.filter(photos.exists)
        let photoBytes = present.reduce(Int64(0)) { total, id in
            total + (photos.url(for: id).map(BackupLocation.size(of:)) ?? 0)
        }
        let recordBytes = rows.reduce(Int64(0)) { $0 + Int64($1.payload.count) }
        return BackupSummary(
            counts: contents.counts, photos: present.count, estimatedBytes: photoBytes + recordBytes * 2 + 4_096,
            includesBodyData: contents.includesBodyData, includesTryOnPhoto: contents.includesTryOnPhoto)
    }

    /// A `records` export of these rows and the photos they point to.
    func export(_ rows: [StoreRow], passphrase: String) throws(BackupError) -> BackupFile {
        let contents = BackupContents(rows)
        let photos = PhotoFiles(directory: location.photos)
        var files: [String: Data] = [:]
        do {
            for codec in RecordCodec.all {
                let kindRows = rows.filter { $0.kind == codec.kind.rawValue }
                guard !kindRows.isEmpty else { continue }
                files[BackupFormat.recordsPath(codec.kind)] = try codec.file(kindRows)
            }
        } catch {
            throw .failed
        }
        let photoFiles = contents.photoIDs.sorted().compactMap { id in photos.url(for: id) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { (BackupFormat.photoPath($0.lastPathComponent), $0) }
        return try write(
            kind: .records, counts: contents.counts, includesBodyData: contents.includesBodyData,
            includesTryOnPhoto: contents.includesTryOnPhoto, data: files, files: photoFiles, passphrase: passphrase)
    }

    /// A `storeCopy` export: the raw store and every photo, for the recovery screen, when this
    /// build can't read the records. The store is copied consistently first (into staging, left
    /// out of backups, deleted straight after).
    func exportStoreCopy(passphrase: String) throws(BackupError) -> BackupFile {
        let scratch = location.staging.appending(path: "StoreCopy-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { BackupLocation.remove(scratch) }
        let copy = scratch.appending(path: "Nook.store")
        do {
            try BackupLocation.prepare(scratch)
            try MigrationCoordinator<NookMigrationPlan>.copyStore(from: location.store.storeURL, to: copy)
            try StoreSQLite.checkpoint(copy)
            guard try StoreSQLite.integrityCheck(copy) == "ok" else { throw BackupError.failed }
        } catch {
            throw .failed
        }
        let photos = PhotoFiles(directory: location.photos)
        let photoFiles = photos.ids().compactMap { id in photos.url(for: id).map { (BackupFormat.photoPath(id), $0) } }
        return try write(
            kind: .storeCopy, counts: BackupCounts(), includesBodyData: false, includesTryOnPhoto: false, data: [:],
            files: [(BackupFormat.storePath, copy)] + photoFiles, passphrase: passphrase)
    }

    private func write(
        kind: BackupManifest.Kind, counts: BackupCounts, includesBodyData: Bool, includesTryOnPhoto: Bool,
        data: [String: Data], files: [(path: String, url: URL)], passphrase: String
    ) throws(BackupError) -> BackupFile {
        var entries: [String: BackupManifest.File] = [:]
        for (path, bytes) in data {
            entries[path] = .init(size: Int64(bytes.count), sha256: BackupFormat.sha256(bytes))
        }
        do {
            for (path, url) in files {
                let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                entries[path] = .init(size: Int64(bytes.count), sha256: BackupFormat.sha256(bytes))
            }
        } catch {
            throw .failed
        }
        let needed = entries.values.reduce(Int64(0)) { $0 + $1.size } + Self.spaceMargin
        let available = freeSpace?() ?? BackupArchiveReader.volumeSpace(at: location.exports)
        guard needed <= available else { throw .notEnoughSpace(needed: needed) }

        let manifest = BackupManifest(
            formatVersion: BackupFormat.formatVersion, kind: kind, payloadVersion: RecordPayload.currentVersion,
            storeVersion: MigrationCoordinator<NookMigrationPlan>.currentVersion, appVersion: AppVersion.version,
            appBuild: AppVersion.build, createdAt: now(), counts: counts, includesBodyData: includesBodyData,
            includesTryOnPhoto: includesTryOnPhoto, files: entries)
        let folder = location.exports.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: BackupFormat.fileName(on: now(), calendar: calendar))
        do {
            try BackupLocation.prepare(folder)
        } catch {
            throw .failed
        }
        let writer = try BackupArchiveWriter(url: url, passphrase: passphrase)
        do {
            try writer.add(path: BackupFormat.manifestPath, data: BackupManifest.encoder().encode(manifest))
            for (path, bytes) in data.sorted(by: { $0.key < $1.key }) {
                try writer.add(path: path, data: bytes)
            }
            for (path, url) in files {
                guard let entry = entries[path] else { throw BackupError.failed }
                try writer.add(path: path, file: url, size: entry.size, sha256: entry.sha256)
            }
            try writer.finish()
        } catch {
            writer.cancel()
            BackupLocation.remove(folder)
            throw (error as? BackupError) ?? .failed
        }
        return BackupFile(url: url, bytes: BackupLocation.size(of: url))
    }
}
