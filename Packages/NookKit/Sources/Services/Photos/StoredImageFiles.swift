import Foundation
import Models
import SwiftData

/// Looks after her image files in the store's folders (Phase 22b): removes photos, cutouts and
/// try-on pictures that no record points to any more, and their thumbnails.
///
/// What counts as pointed to is read from the store each time, through the same reading the
/// backups use (`BackupContents.photoIDs`): pieces and their cutouts, pieces in Recently deleted,
/// unsaved drafts and what they started from, the try-on photo, stored try-on pictures, and copies
/// kept from a restore to review. So a file shared by two records stays until both have gone, and
/// a file is never removed while the store can't be read.
///
/// - `release` runs when the screens say records went: a piece deleted for good (with
///   `deletedForGood`, also from the restore's safety copy, 0004 section 1), or a deleted picture
///   once its Undo has gone.
/// - `removeUnused` runs at launch. It finds what an edit, a discarded draft, a restore or a kill
///   left behind, and anything in the photo folder that isn't a photo (an interrupted write). Files
///   written since launch are left alone (`NewPhotoFiles`), since the draft that will point to one
///   may not be saved yet.
///
/// Both hold `PhotoFolderLock`, as a restore and Undo restore do, so neither ever sees the
/// folder and the store half way through a restore.
public struct StoredImageFiles: ImageFiles {
    let container: ModelContainer
    let location: BackupLocation
    public let thumbnails: ThumbnailCache

    public init(container: ModelContainer, location: BackupLocation, thumbnails: ThumbnailCache) {
        self.container = container
        self.location = location
        self.thumbnails = thumbnails
    }

    public func release(_ photos: [PhotoReference], deletedForGood: Bool) async {
        let ids = Set(photos.compactMap(Self.storedID))
        guard !ids.isEmpty else { return }
        await Self.release(ids, deletedForGood: deletedForGood, in: self)
    }

    public func removeUnused() async {
        await Self.removeUnused(in: self)
    }

    // MARK: Away from the main actor

    @concurrent
    private static func release(_ ids: Set<String>, deletedForGood: Bool, in files: StoredImageFiles) async {
        files.releaseNow(ids, deletedForGood: deletedForGood)
    }

    @concurrent
    private static func removeUnused(in files: StoredImageFiles) async {
        files.removeUnusedNow()
    }

    func releaseNow(_ ids: Set<String>, deletedForGood: Bool) {
        PhotoFolderLock.run {
            guard let referenced = referencedIDs() else { return }
            let unused = ids.subtracting(referenced)
            let photos = PhotoFiles(directory: location.photos)
            for id in unused { photos.remove(id) }
            thumbnails.remove(unused)
            if deletedForGood {
                let safety = PhotoFiles(directory: location.safetyPhotos)
                for id in unused { safety.remove(id) }
            }
        }
    }

    func removeUnusedNow() {
        PhotoFolderLock.run {
            guard let referenced = referencedIDs() else { return }
            let new = NewPhotoFiles.shared.all
            let names = (try? FileManager.default.contentsOfDirectory(atPath: location.photos.path)) ?? []
            var kept: Set<String> = []
            for name in names {
                if PhotoFiles.isPlainID(name), referenced.contains(name) || new.contains(name) {
                    kept.insert(name)
                } else {
                    try? FileManager.default.removeItem(at: location.photos.appending(path: name))
                }
            }
            thumbnails.removeAll(except: kept)
        }
    }

    /// The photo IDs the store's records point to, or `nil` when the store can't be read.
    private func referencedIDs() -> Set<String>? {
        guard let rows = try? StoreRow.all(in: ModelContext(container)) else { return nil }
        return BackupContents(rows).photoIDs
    }

    private static func storedID(_ photo: PhotoReference) -> String? {
        if case .stored(let id) = photo { id.rawValue } else { nil }
    }
}

/// Held while the photo folder and the store change together: a restore, Undo restore, and
/// `StoredImageFiles` removing files.
enum PhotoFolderLock {
    private static let lock = NSRecursiveLock()

    static func run<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

extension PhotoFiles {
    /// Removes one photo. Removing one that isn't there is fine.
    func remove(_ id: String) {
        guard let url = url(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
