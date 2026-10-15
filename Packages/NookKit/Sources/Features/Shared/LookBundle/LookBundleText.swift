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

    /// A piece's name, saying when she doesn't own it.
    static func spokenName(of piece: LookBundlePiece) -> String {
        guard piece.isIdea else { return piece.name }
        return String(
            localized: "\(piece.name) (not in your closet)", bundle: .module,
            comment: "Spoken name of a look's piece she doesn't own")
    }
}
