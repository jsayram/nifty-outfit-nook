import Foundation
import Models
import Synchronization

/// Her photo files on the iPhone (Phase 22a): one file per photo in `Application Support/Photos`,
/// named by the photo's ID, with Data Protection `complete`.
///
/// It's the folder Phase 21b's backups carry (`BackupLocation.photos`), read and named the same
/// way (`PhotoFiles`: a UUID, no extension), and it stays in device backups as the store does
/// (0004 section 2). Delete my data removes it with the backups' files (`BackupDataEraser`). The
/// files are always the cleaned copy from `PhotoCleaner`, never the bytes she picked.
///
/// Phase 22b: originals and cutouts sit side by side here, each its own file, and so do stored
/// try-on pictures. A new file is only written when the iPhone keeps `reserve` free afterwards,
/// so a photo never takes the last of the space the store needs. Thumbnails live apart, in
/// `ThumbnailCache`, and files nothing points to are removed by `StoredImageFiles`.
public struct PhotoFileStore: Hashable, Sendable {
    public let directory: URL
    /// The space left free after a new file is written: 50 MB.
    public static let reserve: Int64 = 50_000_000
    /// Free space for tests. `nil` reads the volume.
    private let freeSpace: SpaceReader?

    public init(directory: URL, freeSpace: (@Sendable () -> Int64)? = nil) {
        self.directory = directory
        self.freeSpace = freeSpace.map(SpaceReader.init)
    }

    /// The app's folder, the one backups carry.
    public static var app: PhotoFileStore { PhotoFileStore(directory: BackupLocation.app.photos) }

    private var files: PhotoFiles { PhotoFiles(directory: directory) }

    /// Writes a new photo and returns its ID. The write is atomic, so a photo is either all there
    /// or not there. Throws `CocoaError(.fileWriteOutOfSpace)` without writing when the iPhone
    /// would be left with less than `reserve`.
    public func add(_ data: Data) throws -> String {
        let available = freeSpace?.read() ?? BackupArchiveReader.volumeSpace(at: directory)
        guard available >= Int64(data.count) + Self.reserve else { throw CocoaError(.fileWriteOutOfSpace) }
        try BackupLocation.prepare(directory, backedUp: true)
        let id = UUID().uuidString.lowercased()
        guard let url = files.url(for: id) else { throw CocoaError(.fileWriteInvalidFileName) }
        // Recorded before the write, so a sweep running now can't take a file nothing points to yet.
        NewPhotoFiles.shared.insert(id)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            NewPhotoFiles.shared.remove(id)
            throw error
        }
        return id
    }

    /// Keeps a cutout next to its photo: the PNG from `CutoutResult`, which carries no metadata,
    /// as a file of its own.
    public func addCutout(_ result: CutoutResult) throws -> GarmentCutout {
        let id = try add(result.imageData)
        let ratio = result.pixelHeight > 0 ? Double(result.pixelWidth) / Double(result.pixelHeight) : nil
        return GarmentCutout(image: .stored(EntityID(id)), quality: result.quality, aspectRatio: ratio)
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

    public static func == (lhs: PhotoFileStore, rhs: PhotoFileStore) -> Bool { lhs.directory == rhs.directory }
    public func hash(into hasher: inout Hasher) { hasher.combine(directory) }
}

/// A free-space reader, boxed so `PhotoFileStore` stays `Hashable`.
private struct SpaceReader: Sendable {
    let read: @Sendable () -> Int64
}

/// The photo files written since launch. A sweep leaves them alone, since the record that will
/// point to one (a draft, a new piece) may not be saved yet. The launch sweep runs before any is
/// written, so a file left behind by a kill is still found the next time.
final class NewPhotoFiles: Sendable {
    static let shared = NewPhotoFiles()
    private let ids = Mutex<Set<String>>([])

    func insert(_ id: String) { _ = ids.withLock { $0.insert(id) } }
    func remove(_ id: String) { _ = ids.withLock { $0.remove(id) } }
    func contains(_ id: String) -> Bool { ids.withLock { $0.contains(id) } }
    var all: Set<String> { ids.withLock { $0 } }
}
