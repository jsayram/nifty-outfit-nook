import Foundation
import Models

/// Her photo files on the iPhone (Phase 22a): one file per photo in `Application Support/Photos`,
/// named by the photo's ID, with Data Protection `complete`.
///
/// It's the folder Phase 21b's backups carry (`BackupLocation.photos`), read and named the same
/// way (`PhotoFiles`: a UUID, no extension), and it stays in device backups as the store does
/// (0004 section 2). Delete my data removes it with the backups' files (`BackupDataEraser`). The
/// files are always the cleaned copy from `PhotoCleaner`, never the bytes she picked.
/// Thumbnails, the cache and disk-space handling come in Phase 22b; this stays a plain folder
/// until then.
public struct PhotoFileStore: Hashable, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's folder, the one backups carry.
    public static var app: PhotoFileStore { PhotoFileStore(directory: BackupLocation.app.photos) }

    private var files: PhotoFiles { PhotoFiles(directory: directory) }

    /// Writes a new photo and returns its ID. The write is atomic, so a photo is either all there
    /// or not there.
    public func add(_ data: Data) throws -> String {
        try BackupLocation.prepare(directory, backedUp: true)
        let id = UUID().uuidString.lowercased()
        guard let url = files.url(for: id) else { throw CocoaError(.fileWriteInvalidFileName) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return id
    }

    /// The photo's bytes, or `nil` when there's no such photo.
    public func data(for id: String) -> Data? {
        guard let url = files.url(for: id) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Removes one photo. Removing one that isn't there is fine.
    public func remove(_ id: String) {
        guard let url = files.url(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Every photo's ID.
    public func ids() -> [String] { files.ids() }

    /// The file for `id`. Only plain IDs name a file, so an ID can never reach outside the folder.
    func url(for id: String) -> URL? { files.url(for: id) }
}
