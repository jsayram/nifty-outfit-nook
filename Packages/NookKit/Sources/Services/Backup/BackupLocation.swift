import Foundation

/// Where backups keep their files (Phase 21b, 0004 sections 1 and 3). Every folder has Data
/// Protection `complete`; every folder but the photos is left out of device backups.
public struct BackupLocation: Hashable, Sendable {
    /// The store, its journal and its migration snapshot.
    public let store: StoreLocation
    /// Her photo files, one per image ID. Nothing writes here until Phase 22a/22b adds real
    /// photos; backups already carry what's here, so the round trip is tested from day one.
    public let photos: URL
    /// A checked copy, unpacked, until it's restored or thrown away. Cleared at every launch.
    public let staging: URL
    /// Finished exports, until the Files sheet has saved them. Cleared at every launch.
    public let exports: URL
    /// Thumbnails of her photos (Phase 22b), made again whenever they're missing. Left out of
    /// backups of every kind, and removed with their photo.
    public let thumbnails: URL

    /// - Parameter thumbnails: `nil` puts them in a `Thumbnails` folder next to `photos`.
    public init(store: StoreLocation, photos: URL, staging: URL, exports: URL, thumbnails: URL? = nil) {
        self.store = store
        self.photos = photos
        self.staging = staging
        self.exports = exports
        self.thumbnails =
            thumbnails ?? photos.deletingLastPathComponent().appending(path: "Thumbnails", directoryHint: .isDirectory)
    }

    /// The app's folders: `Application Support/Photos` and `Application Support/Restore`,
    /// `tmp/Export` and `Library/Caches/Thumbnails`.
    public static var app: BackupLocation {
        BackupLocation(
            store: .app,
            photos: URL.applicationSupportDirectory.appending(path: "Photos", directoryHint: .isDirectory),
            staging: URL.applicationSupportDirectory.appending(path: "Restore", directoryHint: .isDirectory),
            exports: URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory),
            thumbnails: URL.cachesDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory))
    }

    /// Everything in one folder, for tests.
    public static func inside(_ directory: URL) -> BackupLocation {
        BackupLocation(
            store: StoreLocation(directory: directory.appending(path: "Store", directoryHint: .isDirectory)),
            photos: directory.appending(path: "Photos", directoryHint: .isDirectory),
            staging: directory.appending(path: "Restore", directoryHint: .isDirectory),
            exports: directory.appending(path: "Export", directoryHint: .isDirectory))
    }

    /// The safety copy taken before a restore: the store and the photos as they were. Kept 7
    /// days for Undo restore. Next to the store, away from the migration's `Recovery` folder,
    /// which a migration clears.
    var safetyCopy: URL { store.directory.appending(path: "RestoreSafetyCopy", directoryHint: .isDirectory) }
    var safetyStore: URL { safetyCopy.appending(path: "Nook.store") }
    var safetyPhotos: URL { safetyCopy.appending(path: "Photos", directoryHint: .isDirectory) }
    var restoreJournal: URL { store.directory.appending(path: "RestoreJournal.json") }

    /// Makes a folder with Data Protection `complete`, and leaves it out of device backups
    /// unless `backedUp`.
    static func prepare(_ url: URL, backedUp: Bool = false) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        guard !backedUp else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = url
        try folder.setResourceValues(values)
    }

    static func remove(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Bytes in a folder and everything under it, read with `fileSizeKey`.
    static func size(of url: URL) -> Int64 {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return 0 }
        guard isFolder.boolValue else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// Her photo files, by image ID. The ID is the file's name, so only plain IDs are allowed.
struct PhotoFiles: Sendable {
    let directory: URL

    func url(for id: String) -> URL? {
        guard Self.isPlainID(id) else { return nil }
        return directory.appending(path: id)
    }

    func exists(_ id: String) -> Bool {
        url(for: id).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Every photo's ID.
    func ids() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter(Self.isPlainID).sorted()
    }

    /// Deletes the photos no record points to any more.
    func removeAll(except kept: Set<String>) {
        for id in ids() where !kept.contains(id) {
            if let url = url(for: id) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// An image ID is letters, digits and hyphens, like a UUID.
    static func isPlainID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64
            && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" }
    }
}
