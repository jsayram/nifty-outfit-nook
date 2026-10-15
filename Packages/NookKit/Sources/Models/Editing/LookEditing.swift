import Foundation

/// Changes to one piece of a look: Swap a piece and Remove this piece (LR-07, LR-08).
///
/// A changed look is a new look with its own ID. It keeps the result and version it came from
/// (so it's still Simple, Dressed up or Something new), its occasion and source, and every other
/// piece as it was (FR-09). It starts unsaved and unnamed, never worn, and without the try-on
/// picture, which showed the earlier look. The look it came from is left as it was, so a saved
/// look stays saved and Undo can go back to it exactly.
public enum LookEditing {
    /// The look with one piece replaced by one of her garments, in the same place.
    ///
    /// - Parameters:
    ///   - simple: the stylist's Simple version, for the "Same as Simple" marks. `nil` for a look
    ///     she made herself.
    /// - Returns: `nil` when the look has no such piece, or already has that garment.
    public static func replacing(
        _ pieceID: LookPiece.ID,
        with garmentID: Garment.ID,
        in look: Look,
        simple: Look?,
        newID: Look.ID,
        at date: Date
    ) -> Look? {
        guard let index = look.pieces.firstIndex(where: { $0.id == pieceID }),
            !look.garmentIDs.contains(garmentID)
        else { return nil }
        var pieces = look.pieces
        pieces[index] = LookPiece(id: LookPiece.ID("\(newID)-\(garmentID)"), content: .garment(garmentID))
        return changed(look, pieces: pieces, simple: simple, newID: newID, at: date)
    }

    /// The look without one piece.
    ///
    /// - Returns: `nil` when the look has no such piece. Whether the rest is still a look is
    ///   `LookRules`' question.
    public static func removing(
        _ pieceID: LookPiece.ID,
        from look: Look,
        simple: Look?,
        newID: Look.ID,
        at date: Date
    ) -> Look? {
        guard look.pieces.contains(where: { $0.id == pieceID }) else { return nil }
        let pieces = look.pieces.filter { $0.id != pieceID }
        return changed(look, pieces: pieces, simple: simple, newID: newID, at: date)
    }

    /// The kinds of piece the look would have without this piece, for checking a removal.
    public static func categories(
        of look: Look,
        without pieceID: LookPiece.ID?,
        garments: [Garment.ID: Garment]
    ) -> [GarmentCategory] {
        look.pieces.filter { $0.id != pieceID }.compactMap { piece in
            switch piece.content {
            case .garment(let id): garments[id]?.category
            case .idea(let idea): idea.category
            }
        }
    }

    private static func changed(
        _ look: Look,
        pieces: [LookPiece],
        simple: Look?,
        newID: Look.ID,
        at date: Date
    ) -> Look {
        let simpleIDs = Set(simple?.garmentIDs ?? [])
        let marked = pieces.map { piece in
            var piece = piece
            piece.isSameAsSimple = piece.garmentID.map(simpleIDs.contains) ?? false
            return piece
        }
        return Look(
            id: newID,
            resultID: look.resultID,
            version: look.version,
            pieces: marked,
            occasion: look.occasion,
            source: look.source,
            createdAt: date
        )
    }
}
