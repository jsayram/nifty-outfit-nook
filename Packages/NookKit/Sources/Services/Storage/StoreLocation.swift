import Foundation

/// Where the store's files live: the SQLite store (with its `-wal` and `-shm`), the migration
/// journal and the recovery snapshot, all in one folder.
///
/// The app's folder is `Application Support/Store`. The store and journal are in her device
/// backup, as iOS does by default (docs/decisions/0004-backup-and-recovery.md, section 2); the
/// recovery snapshot isn't. Every file has Data Protection `complete`: the app's entitlement
/// makes it the default, and the folder and files are also given it in code.
public struct StoreLocation: Hashable, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's store.
    public static var app: StoreLocation {
        StoreLocation(directory: URL.applicationSupportDirectory.appending(path: "Store", directoryHint: .isDirectory))
    }

    public var storeURL: URL { directory.appending(path: "Nook.store") }
    /// The store and the two files SQLite keeps beside it.
    var storeFiles: [URL] { ["", "-wal", "-shm"].map { URL(filePath: storeURL.path + $0) } }
    var journalURL: URL { directory.appending(path: "MigrationJournal.json") }
    /// The safety copy taken before a migration. Left out of device backups.
    public var recoveryDirectory: URL { directory.appending(path: "Recovery", directoryHint: .isDirectory) }
    var snapshotURL: URL { recoveryDirectory.appending(path: "Snapshot.store") }

    /// Makes the folder, with Data Protection `complete`, if it isn't there.
    func makeDirectory() throws {
        try Self.makeProtectedDirectory(directory)
    }

    static func makeProtectedDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
    }

    /// Gives every store file that exists Data Protection `complete`. New files get it from the
    /// app's entitlement anyway; this makes sure of it in code.
    func protectStoreFiles() {
        for url in storeFiles where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        }
    }

    /// Removes everything: the store, the journal and the snapshot. Only the tests call it; Delete
    /// my data erases the records through the stores, with the store open.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
