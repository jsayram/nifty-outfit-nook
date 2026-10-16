import Foundation
import Models

/// The words a look bundle and its piece list use.
enum LookBundleText {
    /// The tag on a piece she doesn't own (LR-05b).
    static var notInYourCloset: String {
        String(localized: "Not in your closet", bundle: .module, comment: "Tag on a look's piece she doesn't own")
    }

    /// What VoiceOver says for the whole bundle: "Look: Cream blouse, Navy trousers, Tan loafers".
    static func summary(of content: LookBundleContent, title: String?, locale: Locale) -> String {
        let title =
            title ?? content.name
            ?? String(localized: "Look", bundle: .module, comment: "Spoken before a look's pieces when it has no name")
        let pieces = content.pieces.map(spokenName(of:)).formatted(.list(type: .and, width: .narrow).locale(locale))
        guard !content.pieces.isEmpty else {
            return String(
                localized: "\(title): no pieces", bundle: .module,
                comment: "Spoken for a look with no pieces left. The look's title.")
        }
        return String(
            localized: "\(title): \(pieces)", bundle: .module,
            comment: "Spoken for a look bundle: the look's title, then its pieces, as in Look: Black tee, Jeans")
    }

    /// A piece's name, saying when she doesn't own it, or no longer has it.
    static func spokenName(of piece: LookBundlePiece) -> String {
        if piece.isIdea {
            return String(
                localized: "\(piece.name) (not in your closet)", bundle: .module,
                comment: "Spoken name of a look's piece she doesn't own")
        }
        if let removal = piece.removal {
            let note = removalNote(removal)
            return String(
                localized: "\(piece.name) (\(note))", bundle: .module,
                comment: "Spoken name of a look's piece that left her closet: the name, then why, in brackets")
        }
        return piece.name
    }

    /// Under a piece that left her closet (LR-16): "No longer in your closet" or "In Recently
    /// deleted".
    static func removalNote(_ removal: PieceRemoval) -> String {
        switch removal {
        case .noLongerOwned:
            String(
                localized: "No longer in your closet", bundle: .module,
                comment: "Mark on a saved look's piece she said she doesn't have any more (LR-16)")
        case .deleted:
            String(
                localized: "In Recently deleted", bundle: .module,
                comment: "Mark on a saved look's piece she deleted, which is in Recently deleted (LR-16)")
        }
    }
}
