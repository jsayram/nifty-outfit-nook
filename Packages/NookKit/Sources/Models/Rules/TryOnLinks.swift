import Foundation

/// How try-on pictures and their looks point at each other (RD-08.2: each picture opens its look,
/// and the look shows its pictures).
///
/// A picture points at its look by ID and keeps the look as it was (`TryOnPicture.captured`). The
/// look never points back, so there's one link to keep right. Deleting a look leaves its pictures
/// (PRD §7.5 and §9.2.4 keep every delivered picture until she deletes it); Undo brings the look
/// back under the same ID, so the link comes back with it.
public enum TryOnLinks {
    /// Where a picture's look is now.
    public enum Status: Hashable, Sendable {
        /// The look is in Saved Looks with the pieces the picture shows.
        case current(Look)
        /// The look is in Saved Looks, but its pieces changed since (a swap): the picture shows an
        /// earlier version.
        case changed(Look)
        /// The look isn't in Saved Looks any more: deleted, or unsaved back into history.
        case notSaved
    }

    /// Where `picture`'s look is now, from every look by ID.
    public static func status(of picture: TryOnPicture, looks: [Look.ID: Look]) -> Status {
        guard let look = looks[picture.lookID], look.isSaved else { return .notSaved }
        return samePieces(picture.captured.pieces, look.pieces) ? .current(look) : .changed(look)
    }

    /// A look's pictures, newest first.
    public static func pictures(of lookID: Look.ID, in pictures: [TryOnPicture]) -> [TryOnPicture] {
        newestFirst(pictures.filter { $0.lookID == lookID })
    }

    /// Pictures newest first, then by ID, so the order never depends on the store.
    public static func newestFirst(_ pictures: [TryOnPicture]) -> [TryOnPicture] {
        pictures.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id < rhs.id
        }
    }

    /// The newest picture that already shows exactly this look's pieces, so Try it on can offer it
    /// before making another (FR-59: reuse a matching picture rather than make a new one).
    public static func reusable(for look: Look, in pictures: [TryOnPicture]) -> TryOnPicture? {
        Self.pictures(of: look.id, in: pictures).first { samePieces($0.captured.pieces, look.pieces) }
    }

    /// True when two piece lists hold the same garments and ideas, in any order. Piece IDs and the
    /// "Same as Simple" marks don't change what a picture shows, so they're ignored.
    public static func samePieces(_ lhs: [LookPiece], _ rhs: [LookPiece]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var remaining = rhs.map(\.content)
        for piece in lhs {
            guard let index = remaining.firstIndex(of: piece.content) else { return false }
            remaining.remove(at: index)
        }
        return true
    }
}
