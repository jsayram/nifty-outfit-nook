import CoreGraphics

/// The size and appearance of one sticker, and the measurements that follow from its size.
///
/// The mockups draw the sticker edge with stacked CSS drop shadows: 3 px on the 216 px piece in
/// `garment.html`, 2.5 px in the `results.html` bundle and 1.2 px on its mini bundles. So the
/// edge and the shadow grow with the sticker instead of staying one width everywhere.
nonisolated public struct StickerSpec: Hashable, Sendable {
    /// The space the sticker takes in a layout, in points. The garment and its white edge fit
    /// inside it; the shadow falls outside it, as a CSS drop shadow does.
    public let size: CGSize
    /// Pixels per point.
    public let scale: CGFloat
    public let appearance: Appearance
    public let placement: Placement

    /// Where the garment sits inside the sticker's size.
    public enum Placement: Hashable, Sendable {
        /// In the middle, for bundles and grids.
        case centred
        /// On the bottom, centred across, so a wide piece such as a shoe rests on a contact
        /// shadow under the sticker instead of floating above it (garment detail).
        case resting
    }

    /// Sizes are rounded to the nearest half point, so a layout that moves by a fraction of a
    /// point doesn't make a new sticker.
    public init(size: CGSize, scale: CGFloat, appearance: Appearance, placement: Placement = .centred) {
        self.size = CGSize(width: (size.width * 2).rounded() / 2, height: (size.height * 2).rounded() / 2)
        self.scale = max(1, scale.rounded())
        self.appearance = appearance
        self.placement = placement
    }

    public var longSide: CGFloat { max(size.width, size.height) }

    /// The white edge around the garment, in points: 1.8% of the long side, between 1.25 and 6.
    /// That's about 4.25 points on garment detail, close to the mockup's stacked 3 px shadows,
    /// 1.6 on a closet-sized piece and the minimum on a small bundle.
    public var edgeWidth: CGFloat { min(6, max(1.25, longSide * 0.018)) }

    /// How far down the shadow falls, in points.
    public var shadowOffset: CGFloat { min(9, max(1.5, longSide * 0.032)) }

    /// How soft the shadow is, in points (Core Graphics' blur).
    public var shadowBlur: CGFloat { min(9, max(1.5, longSide * 0.03)) }

    /// How far the picture reaches past `size` on each side, in points, to hold the shadow.
    public var bleed: CGFloat { (shadowOffset + shadowBlur).rounded(.up) }

    /// The size in pixels, at least one by one.
    var pixelWidth: Int { max(1, Int((size.width * scale).rounded())) }
    var pixelHeight: Int { max(1, Int((size.height * scale).rounded())) }
    var bleedPixels: Int { Int((bleed * scale).rounded(.up)) }
}

/// A sticker drawn by `StickerRenderer`: the garment, its white edge and its shadow in one
/// picture, made once and cached.
nonisolated public struct StickerArtwork: Sendable {
    public let image: CGImage
    public let spec: StickerSpec

    /// How far the picture reaches past the sticker's size on each side, in points.
    public var bleed: CGFloat { CGFloat(spec.bleedPixels) / spec.scale }

    /// The memory the picture holds, for the cache's budget.
    public var byteCount: Int { image.bytesPerRow * image.height }
}
