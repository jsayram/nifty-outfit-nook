import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Small copies of her photos on disk (Phase 22b), so a long closet grid reads a 40 KB file per
/// cell instead of decoding a 12 MP photo.
///
/// Each image gets at most two: 512 pixels on the long side for grids and 1,024 for detail
/// screens. Larger requests read the photo itself. A thumbnail is made the first time it's asked
/// for and written next to the others with Data Protection `complete`; it's JPEG, or PNG when the
/// image has transparency (a cutout). HEIC would be smaller, but encoding it hangs on the
/// simulator (Phase 22a), so it waits for a device test.
///
/// The folder is a cache: `Library/Caches/Thumbnails`, left out of every backup, and anything in
/// it can be made again. It holds at most `byteLimit`; past that, thumbnails not used since launch
/// go first, then the least recently used, down to three quarters of the limit. No file dates are
/// read (they'd need a privacy manifest reason); the order is kept in memory. When the iPhone is
/// short of space (`minimumFreeSpace`), nothing new is written and the thumbnail is only returned.
/// A failed write is never an error: the caller still gets its thumbnail.
///
/// A thumbnail belongs to its image: `remove(_:)` and `removeAll(except:)` take them away with
/// it (`StoredImageFiles`), and Delete my data removes the folder (`BackupDataEraser`).
public final class ThumbnailCache: Sendable {
    /// The thumbnail sizes, smallest first.
    public static let sizes = [512, 1_024]

    public let directory: URL
    public let byteLimit: Int64
    public let minimumFreeSpace: Int64
    private let freeSpace: @Sendable () -> Int64
    private let state = Mutex(State())

    private struct State {
        /// Bytes of each thumbnail file, by file name, once the folder has been read.
        var sizes: [String: Int64]?
        var total: Int64 = 0
        /// When each file was last used this run, as a counter.
        var lastUse: [String: UInt64] = [:]
        var clock: UInt64 = 0
        /// How many thumbnails were made (rather than read), for tests and measuring.
        var made = 0
    }

    /// - Parameters:
    ///   - byteLimit: 200 MB holds the 512-pixel thumbnails of about 5,000 photos.
    ///   - minimumFreeSpace: below this, thumbnails aren't written.
    ///   - freeSpace: the volume's free space, for tests. `nil` reads it.
    public init(
        directory: URL, byteLimit: Int64 = 200_000_000, minimumFreeSpace: Int64 = 500_000_000,
        freeSpace: (@Sendable () -> Int64)? = nil
    ) {
        self.directory = directory
        self.byteLimit = byteLimit
        self.minimumFreeSpace = minimumFreeSpace
        self.freeSpace = freeSpace ?? { [directory] in BackupArchiveReader.volumeSpace(at: directory) }
    }

    /// The thumbnail size that serves `maxPixelSize`, or `nil` when it's bigger than any.
    public static func size(for maxPixelSize: Int) -> Int? {
        sizes.first { $0 >= maxPixelSize }
    }

    /// The thumbnail of image `id` for `maxPixelSize`: read from disk, or made from `original`
    /// and kept. `nil` when the size is bigger than any thumbnail, or the original can't be read.
    public func data(for id: String, maxPixelSize: Int, original: () -> Data?) -> Data? {
        guard let size = Self.size(for: maxPixelSize), PhotoFiles.isPlainID(id) else { return nil }
        let name = Self.fileName(id, size: size)
        let url = directory.appending(path: name)
        if let kept = try? Data(contentsOf: url, options: .mappedIfSafe), !kept.isEmpty {
            touch(name)
            return kept
        }
        guard let source = original(), let thumbnail = Self.make(from: source, size: size) else { return nil }
        state.withLock { $0.made += 1 }
        write(thumbnail, name: name)
        return thumbnail
    }

    /// How many thumbnails were made rather than read.
    public var made: Int { state.withLock { $0.made } }

    /// The thumbnails' bytes on disk.
    public var bytes: Int64 {
        loadSizes()
        return state.withLock { $0.total }
    }

    /// Removes the thumbnails of these images.
    public func remove(_ ids: some Sequence<String>) {
        let ids = Set(ids)
        guard !ids.isEmpty else { return }
        removeFiles { ids.contains(Self.imageID(inFileName: $0) ?? "") }
    }

    /// Removes every thumbnail whose image isn't in `kept`, and anything else in the folder.
    public func removeAll(except kept: Set<String>) {
        removeFiles { name in Self.imageID(inFileName: name).map { !kept.contains($0) } ?? true }
    }

    // MARK: Files

    static func fileName(_ id: String, size: Int) -> String { "\(id)-\(size)" }

    /// The image ID in a thumbnail's file name, or `nil` for a name that isn't one.
    static func imageID(inFileName name: String) -> String? {
        guard let dash = name.lastIndex(of: "-"), let size = Int(name[name.index(after: dash)...]),
            sizes.contains(size)
        else { return nil }
        let id = String(name[..<dash])
        return PhotoFiles.isPlainID(id) ? id : nil
    }

    private func touch(_ name: String) {
        state.withLock { state in
            state.clock += 1
            state.lastUse[name] = state.clock
        }
    }

    private func write(_ data: Data, name: String) {
        guard freeSpace() >= minimumFreeSpace + Int64(data.count) else {
            // Short of space: make room by halving the cache, and keep this one in memory only.
            trim(to: bytes / 2)
            return
        }
        do {
            try BackupLocation.prepare(directory)
            try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtection])
        } catch {
            return
        }
        loadSizes()
        let over = state.withLock { state -> Bool in
            state.total += Int64(data.count) - (state.sizes?[name] ?? 0)
            state.sizes?[name] = Int64(data.count)
            state.clock += 1
            state.lastUse[name] = state.clock
            return state.total > byteLimit
        }
        if over { trim(to: byteLimit / 4 * 3) }
    }

    /// Removes thumbnails until at most `target` bytes are left: those not used since launch
    /// first, then the least recently used.
    func trim(to target: Int64) {
        loadSizes()
        let doomed = state.withLock { state -> [String] in
            guard let sizes = state.sizes, state.total > target else { return [] }
            let order = sizes.keys.sorted { (state.lastUse[$0] ?? 0, $0) < (state.lastUse[$1] ?? 0, $1) }
            var total = state.total
            var doomed: [String] = []
            for name in order where total > target {
                total -= sizes[name] ?? 0
                doomed.append(name)
            }
            return doomed
        }
        let set = Set(doomed)
        removeFiles { set.contains($0) }
    }

    private func removeFiles(where shouldRemove: (String) -> Bool) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var removed: [String] = []
        for name in names where shouldRemove(name) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
            removed.append(name)
        }
        guard !removed.isEmpty else { return }
        state.withLock { state in
            for name in removed {
                state.total -= state.sizes?.removeValue(forKey: name) ?? 0
                state.lastUse[name] = nil
            }
        }
    }

    /// Reads the folder's sizes once, with `fileSizeKey` only.
    private func loadSizes() {
        guard state.withLock({ $0.sizes == nil }) else { return }
        var sizes: [String: Int64] = [:]
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files {
            sizes[file.lastPathComponent] = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        state.withLock { state in
            guard state.sizes == nil else { return }
            state.sizes = sizes
            state.total = sizes.values.reduce(0, +)
        }
    }

    // MARK: Making one

    /// A thumbnail of `data` no larger than `size` on its long side, upright: JPEG, or PNG when it
    /// has transparency. Built from the pixels alone, so no metadata comes along.
    static func make(from data: Data, size: Int) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let hasAlpha =
            switch image.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: false
            default: true
            }
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { return nil }
        let properties = hasAlpha ? nil : [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination), output.length > 0 else { return nil }
        return output as Data
    }
}
