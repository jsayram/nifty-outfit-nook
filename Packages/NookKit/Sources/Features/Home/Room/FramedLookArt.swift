import DesignSystem
import Models
import SwiftUI

/// A saved look drawn small inside a frame under the shelf (`home.html`): a top over a bottom, or
/// a dress, standing in the card. Decoration only; the frame's button names the look.
struct FramedLookArt: View {
    let look: FramedLook
    /// The room's scale, from stage units to points.
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(boxes.enumerated()), id: \.offset) { _, item in
                let (piece, box) = item
                GarmentPicture(
                    photo: piece.photo, cutout: piece.cutout, category: piece.category, colors: piece.colors,
                    size: CGSize(width: box.width * scale, height: box.height * scale)
                )
                .frame(width: box.width * scale, height: box.height * scale)
                .offset(x: box.minX * scale, y: box.minY * scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Each piece with its box in the card, in stage units.
    private var boxes: [(FramedLook.Piece, CGRect)] {
        switch look.pieces.count {
        case 0: []
        case 1: [(look.pieces[0], RoomStage.frameDress)]
        default: [(look.pieces[0], RoomStage.frameUpper), (look.pieces[1], RoomStage.frameLower)]
        }
    }
}
