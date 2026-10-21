import Foundation

/// Her image files on the iPhone, seen from the screens (Phase 22b): photos, cutouts and stored
/// try-on pictures, with the thumbnails made from them.
///
/// A file goes when nothing points to it any more. The screens say when that happens (a piece
/// deleted for good, a picture whose Undo has gone), and the app also sweeps at launch for files
/// left behind by an edit, a discarded draft or a kill part way. A file that a record still points
/// to is never removed, so passing one by mistake is safe.
public protocol ImageFiles: Sendable {
    /// Removes the files of `photos` that no record points to any more, and their thumbnails.
    /// With `deletedForGood`, they also go from the restore's safety copy, so Undo restore can't
    /// bring them back (PRD §15.4, decision 0004 section 1).
    func release(_ photos: [PhotoReference], deletedForGood: Bool) async
    /// Removes every file no record points to, and every thumbnail whose image is gone.
    func removeUnused() async
}

/// No files to look after: the debug sample closet in memory, previews and most tests.
public struct NoImageFiles: ImageFiles {
    public init() {}
    public func release(_ photos: [PhotoReference], deletedForGood: Bool) async {}
    public func removeUnused() async {}
}

extension TryOnPicture {
    /// The stored image of a generated picture, if it has one.
    public var storedImage: PhotoReference? {
        if case .generated(let photo) = image, case .stored = photo { photo } else { nil }
    }
}

extension Garment {
    /// The photo and the cutout made from it: the files a piece points to.
    public var imageReferences: [PhotoReference] {
        [photo] + (cutout.map { [$0.image] } ?? [])
    }
}
