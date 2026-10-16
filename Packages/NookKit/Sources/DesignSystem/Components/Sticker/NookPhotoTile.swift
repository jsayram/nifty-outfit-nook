import SwiftUI

/// The fallback for a garment photo without a clean cutout (RD-07.2): the photo itself in a
/// soft rounded tile with a shadow below, and no outline, as the soft style asks.
///
/// It takes exactly `size`, the same as a `NookSticker` would, so a piece that falls back to its
/// tile never moves the layout. The photo fills the tile, cropped from the centre; pass a photo
/// already cropped to frame the garment. The corners are a little rounder on a bigger tile, up
/// to the room tiles' 24 points. Without a photo yet it shows a soft tint of the same shape.
public struct NookPhotoTile: View {
    private let image: CGImage?
    private let size: CGSize

    @Environment(\.displayScale) private var displayScale

    public init(_ image: CGImage?, size: CGSize) {
        self.image = image
        self.size = size
    }

    /// The corner radius for a tile of `size`: an eighth of its short side, between 8 and 24.
    public static func cornerRadius(for size: CGSize) -> CGFloat {
        min(NookRadius.tile, max(8, min(size.width, size.height) / 8))
    }

    /// The larger soft shadow on detail-sized tiles, the small one on closet-sized tiles.
    public static func shadow(for size: CGSize) -> SoftShadow {
        max(size.width, size.height) >= 150 ? .dropLarge : .drop
    }

    public var body: some View {
        let shape = NookRadius.shape(Self.cornerRadius(for: size))
        ZStack {
            Color.nook.tint
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .softShadow(Self.shadow(for: size), in: shape)
        .accessibilityHidden(true)
    }
}
