import Foundation
import Models

/// One saved look as Saved Looks shows it, worked out once when the looks load (playbook,
/// Phase 6): its bundle, its name, the occasion line, and what search and the filters match.
/// Spoken text is built in the cell, so only the cells on screen pay for it.
struct SavedLookItem: Identifiable, Hashable {
    let look: Look
    let content: LookBundleContent
    /// Her name for it, or the occasion's look ("Office look") for one saved without a name.
    let name: String
    /// The occasion's name, if the look has one.
    let occasion: String?
    /// Her pieces in it that have left her closet (LR-16.4).
    let removedCount: Int
    /// The pieces as the filter sees them (`LookFilter`).
    let filterPieces: [LookFilter.Piece]
    /// More words search finds it by: the occasion, and the names of its pieces' kinds and
    /// colours ("Shoes", "Black").
    let searchWords: [String]

    var id: Look.ID { look.id }

    init(_ look: Look, garments: [Garment.ID: Garment]) {
        self.look = look
        content = LookBundleContent(look: look, garments: garments)
        occasion = look.occasion?.title
        name = look.name ?? SavedLooksText.unnamed(occasion: occasion)
        removedCount = content.removed.count
        filterPieces = LookFilter.pieces(of: look, garments: garments)
        var words = occasion.map { [$0] } ?? []
        for piece in filterPieces {
            words.append(piece.category.chipTitle)
            words.append(piece.category.singularTitle)
            words += piece.colors.map(\.title)
        }
        searchWords = words
    }

    func matches(_ filter: LookFilter) -> Bool {
        filter.matches(name: name, pieces: filterPieces, extraWords: searchWords)
    }
}
