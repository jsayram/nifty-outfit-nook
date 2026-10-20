import Foundation
import Models

/// Her photo files on the iPhone (Phase 22a): one file per photo in `Application Support/Photos`,
/// named by the photo's ID, with Data Protection `complete`.
///
/// It's the folder Phase 21b's backups carry, with the same naming (a UUID, no extension), and
/// it stays in device backups as the store does (0004 section 2). The files are always the
/// cleaned copy from `PhotoCleaner`, never the bytes she picked. Thumbnails, the cache and disk
/// space handling come in Phase 22b; this stays a plain folder until then.
public struct PhotoFileStore: Hashable, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's folder.
    public static var app: PhotoFileStore {
        PhotoFileStore(
            directory: URL.applicationSupportDirectory.appending(path: "Photos", directoryHint: .isDirectory))
    }

    /// Writes a new photo and returns its ID. The write is atomic, so a photo is either all there
    /// or not there.
    public func add(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let id = UUID().uuidString.lowercased()
        guard let url = url(for: id) else { throw CocoaError(.fileWriteInvalidFileName) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return id
    }

    /// The photo's bytes, or `nil` when there's no such photo.
    public func data(for id: String) -> Data? {
        guard let url = url(for: id) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    public func contains(_ id: String) -> Bool {
        url(for: id).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Removes one photo. Removing one that isn't there is fine.
    public func remove(_ id: String) {
        guard let url = url(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Every photo's ID.
    public func ids() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter(Self.isPlainID).sorted()
    }

    /// The file for `id`. Only plain IDs (letters, digits and hyphens, like a UUID) name a file,
    /// so an ID can never reach outside the folder.
    func url(for id: String) -> URL? {
        guard Self.isPlainID(id) else { return nil }
        return directory.appending(path: id)
    }

    static func isPlainID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64
            && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" }
    }
}

/// Delete my data's part for photos: the whole folder, garment photos and the try-on photo.
public struct PhotoFilesEraser: ErasableStore {
    let files: PhotoFileStore

    public init(files: PhotoFileStore) {
        self.files = files
    }

    public func eraseAll() async throws(StoreError) {
        guard FileManager.default.fileExists(atPath: files.directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: files.directory)
        } catch {
            throw .unavailable
        }
    }
}
