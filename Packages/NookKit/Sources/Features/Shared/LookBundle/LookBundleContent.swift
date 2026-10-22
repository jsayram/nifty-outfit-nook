import DesignSystem
import Foundation
import Models

/// What a look bundle shows: the look's pieces with what's needed to draw and name each one.
///
/// A `Look` only holds garment IDs, so a screen builds this from the look and the garments it
/// has loaded. Pieces are in body order (layer, top, dress, bottom, shoes, bag, accessory), so
/// the spoken summary and the list under the bundle read top to bottom.
struct LookBundleContent: Identifiable, Hashable {
    /// The look's ID.
    let id: String
    /// Seeds the layout, so a look lies the same way on every screen. The look's ID, or for a
    /// look changed in Swap, the ID of the look it came from, so a swap doesn't toss the others.
    let layoutSeed: String
    /// The look's name, when she's named it.
    let name: String?
    let pieces: [LookBundlePiece]
    /// A try-on picture's photo of her wearing the look, when it has one (a generated picture,
    /// or in the fixtures a sample preview). Only try-on pictures set it; a bundle drawn from the
    /// pieces ignores it.
    var tryOnPhoto: PhotoReference?
    /// 33a: a real picture of her, made from her try-on photo: no Simulated badge.
    var isRealPicture = false

    init(id: String, name: String? = nil, layoutSeed: String? = nil, pieces: [LookBundlePiece]) {
        self.id = id
        self.layoutSeed = layoutSeed ?? id
        self.name = name
        self.pieces = pieces.enumerated()
            .sorted { ($0.element.category.listOrder, $0.offset) < ($1.element.category.listOrder, $1.offset) }
            .map(\.element)
    }

    /// The look's pieces. A garment that isn't in `garments` (purged from Recently deleted) is
    /// left out, since there's nothing left to draw or name.
    init(look: Look, garments: [Garment.ID: Garment], layoutSeed: String? = nil) {
        self.init(
            id: look.id.rawValue,
            name: look.name,
            layoutSeed: layoutSeed,
            pieces: look.pieces.compactMap { piece in
                switch piece.content {
                case .garment(let id):
                    garments[id].map {
                        LookBundlePiece(id: piece.id.rawValue, garment: $0, isSameAsSimple: piece.isSameAsSimple)
                    }
                case .idea(let idea):
                    LookBundlePiece(id: piece.id.rawValue, idea: idea)
                }
            })
    }

    /// The pieces she doesn't own ("Not in your closet").
    var ideas: [LookBundlePiece] { pieces.filter(\.isIdea) }

    /// Her pieces that have left her closet since the look was made (LR-16.4).
    var removed: [LookBundlePiece] { pieces.filter(\.isRemoved) }
}

/// Why one of her garments in a look is no longer in her closet (LR-16).
enum PieceRemoval: Hashable {
    /// "I don't have it any more", or put away in the archive, which has no screen yet.
    case noLongerOwned
    /// In Recently deleted, for 30 days.
    case deleted

    /// `nil` while the garment is in her closet.
    init?(_ garment: Garment) {
        if garment.isInCloset { return nil }
        self = garment.isDeleted ? .deleted : .noLongerOwned
    }
}

/// One piece in a look bundle: a garment of hers, or an idea for one she doesn't own (LR-05b).
struct LookBundlePiece: Identifiable, Hashable {
    let id: String
    let name: String
    let category: GarmentCategory
    let colors: [ColorName]
    let photo: PhotoReference
    let cutout: GarmentCutout?
    /// A piece she doesn't own, drawn from its kind and colours and tagged "Not in your closet".
    let isIdea: Bool
    /// The same piece as in the Simple version ("Same as Simple", LR-05a.3).
    let isSameAsSimple: Bool
    /// Why a garment of hers is no longer in her closet, if it isn't (LR-16). The bundle shows
    /// it faded, and saved looks offer Swap it.
    let removal: PieceRemoval?

    init(
        id: String, name: String, category: GarmentCategory, colors: [ColorName], photo: PhotoReference = .noPhoto,
        cutout: GarmentCutout? = nil, isIdea: Bool = false, isSameAsSimple: Bool = false, removal: PieceRemoval? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.colors = colors
        self.photo = photo
        self.cutout = cutout
        self.isIdea = isIdea
        self.isSameAsSimple = isSameAsSimple
        self.removal = removal
    }

    init(id: String, garment: Garment, isSameAsSimple: Bool = false) {
        self.init(
            id: id, name: garment.name, category: garment.category, colors: garment.colors, photo: garment.photo,
            cutout: garment.cutout, isSameAsSimple: isSameAsSimple, removal: PieceRemoval(garment))
    }

    /// True when the piece is a garment she no longer has in her closet.
    var isRemoved: Bool { removal != nil }

    /// An idea has no photo: it's drawn from its kind and colours.
    init(id: String, idea: PieceIdea) {
        self.init(id: id, name: idea.name, category: idea.category, colors: idea.colors, isIdea: true)
    }

    /// The piece as the bundle's layout sees it: its role, and its cutout's shape when it shows
    /// as a sticker from a photo.
    var bundleItem: BundleItem {
        guard !isIdea, case .cutout = GarmentArtChoice(photo: photo, cutout: cutout),
            let aspect = cutout?.aspectRatio
        else { return BundleItem(role) }
        return BundleItem(role, aspectRatio: CGFloat(aspect))
    }

    /// Where the piece lies in the bundle.
    var role: BundleRole {
        switch category {
        case .top: .top
        case .bottom: .bottom
        case .dress: .dress
        case .layer: .layer
        case .shoes: .shoes
        case .bag: .bag
        case .accessory: .accessory
        }
    }
}
