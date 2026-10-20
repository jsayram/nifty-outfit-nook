import Foundation

// Phase 20a persistence spike: an export that includes the original photos, and a restore that
// checks everything before it touches the app's data (PRD 11.7, "original-inclusive
// export/restore").
//
// The archive is a folder: a consistent copy of the store, every image file, and a manifest with
// the schema version, the record IDs and each file's hash. Encrypting it (SECURITY_STANDARD.md
// section 4) and where it's saved are Phase 20b's design; the spike proves the contents and the
// checks.

struct SpikeArchiveManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var store: SpikeManifest
    /// Every image file in the archive, by name, with its hash.
    var files: [String: String]
}

enum SpikeArchiveError: Error, Equatable {
    case unknownSchema(Int)
    case damagedFiles([String])
    case missingFiles([String])
    case damagedStore(String)
}

enum SpikeArchive {
    static func export(from location: SpikeStoreLocation, to folder: URL) throws -> SpikeArchiveManifest {
        let coordinator = SpikeMigrationCoordinator(location: location)
        guard let version = try coordinator.storedVersion() else { throw SpikeArchiveError.unknownSchema(0) }
        let archiveImages = folder.appending(path: "Images")
        try FileManager.default.createDirectory(at: archiveImages, withIntermediateDirectories: true)
        try SpikeMigrationCoordinator.copyStore(from: location.storeURL, to: folder.appending(path: "Closet.store"))
        let images = SpikeImageFiles(directory: location.imagesDirectory)
        var files: [String: String] = [:]
        for name in try images.names() {
            let data = try images.read(name)
            try data.write(to: archiveImages.appending(path: name))
            files[name] = SpikeImageFiles.sha256(data)
        }
        let manifest = SpikeArchiveManifest(
            schemaVersion: version.rawValue,
            store: try SpikeSQLite.manifest(of: folder.appending(path: "Closet.store"), images: archiveImages),
            files: files)
        try JSONEncoder().encode(manifest).write(to: folder.appending(path: "Manifest.json"))
        return manifest
    }

    /// Checks the whole archive first; only then copies it into `location`, which must be empty
    /// (a wiped app, or a new device). An older schema is migrated by the normal open.
    static func restore(from folder: URL, into location: SpikeStoreLocation) throws -> SpikeArchiveManifest {
        let manifest = try JSONDecoder().decode(
            SpikeArchiveManifest.self, from: Data(contentsOf: folder.appending(path: "Manifest.json")))
        guard SpikeStoreVersion(rawValue: manifest.schemaVersion) != nil else {
            throw SpikeArchiveError.unknownSchema(manifest.schemaVersion)
        }
        let archiveImages = SpikeImageFiles(directory: folder.appending(path: "Images"))
        var damaged: [String] = []
        var missing: [String] = []
        for (name, hash) in manifest.files.sorted(by: { $0.key < $1.key }) {
            guard let file = try archiveImages.describe(name) else {
                missing.append(name)
                continue
            }
            if file.sha256 != hash { damaged.append(name) }
        }
        guard missing.isEmpty else { throw SpikeArchiveError.missingFiles(missing) }
        guard damaged.isEmpty else { throw SpikeArchiveError.damagedFiles(damaged) }
        let archivedStore = folder.appending(path: "Closet.store")
        let integrity = try SpikeSQLite.integrityCheck(archivedStore)
        guard integrity == "ok" else { throw SpikeArchiveError.damagedStore(integrity) }
        let storeManifest = try SpikeSQLite.manifest(of: archivedStore, images: folder.appending(path: "Images"))
        guard storeManifest == manifest.store else { throw SpikeArchiveError.damagedStore("manifest differs") }

        let images = SpikeImageFiles(directory: location.imagesDirectory)
        for name in manifest.files.keys.sorted() { try images.write(try archiveImages.read(name), named: name) }
        try SpikeMigrationCoordinator.copyStore(from: archivedStore, to: location.storeURL)
        return manifest
    }
}
