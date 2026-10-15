import Foundation
import Models

/// One try-on picture as the Pictures tab shows it, worked out once when the pictures load: what
/// it shows, where its look is now, and what search and the filters match.
///
/// Search and the filters look at the look the picture came from (RD-08): the pieces the picture
/// shows, under the look's name now, or its name then if it has left Saved Looks.
struct SavedPictureItem: Identifiable, Hashable {
    let picture: TryOnPicture
    /// What the picture shows: its pieces when it was made.
    let content: LookBundleContent
    /// The look as it is now, for the link to it; what the picture shows once the look has gone.
    let lookContent: LookBundleContent
    /// Where its look is now.
    let status: TryOnLinks.Status
    /// The look's name: as it is now, or as it was if the look isn't saved any more.
    let lookName: String
    /// The picture's look as search and the filters see it.
    let filterLook: SavedLookItem

    var id: TryOnPicture.ID { picture.id }

    init(_ picture: TryOnPicture, looks: [Look.ID: Look], garments: [Garment.ID: Garment]) {
        self.picture = picture
        content = LookBundleContent(picture: picture, garments: garments)
        status = TryOnLinks.status(of: picture, looks: looks)
        let current = status.look
        let shown = Look(
            id: picture.lookID, pieces: picture.captured.pieces, name: current?.name ?? picture.captured.name,
            occasion: current?.occasion ?? picture.captured.occasion, createdAt: picture.createdAt)
        filterLook = SavedLookItem(shown, garments: garments)
        lookName = filterLook.name
        lookContent = current.map { LookBundleContent(look: $0, garments: garments) } ?? content
    }

    /// The look to open from the picture, when it's still in Saved Looks.
    var look: Look? { status.look }

    func matches(_ filter: LookFilter) -> Bool {
        filterLook.matches(filter)
    }
}

extension TryOnLinks.Status {
    /// The look, when it's still in Saved Looks.
    var look: Look? {
        switch self {
        case .current(let look), .changed(let look): look
        case .notSaved: nil
        }
    }
}
