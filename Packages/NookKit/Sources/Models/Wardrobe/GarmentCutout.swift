import Foundation

/// A garment lifted out of its photo (Phase 8b): where the cutout picture is, and the signals
/// from the cutout step that say how clean it looks.
///
/// Data tier: **Personal**, like the photo it comes from (DATA_MAP.md). The picture is a PNG
/// with no metadata (`CutoutResult`). Where it's stored is decided with the photo store
/// (Phase 22).
public struct GarmentCutout: Hashable, Sendable, Codable {
    /// The cutout picture: the piece on a transparent background.
    public var image: PhotoReference
    public var quality: CutoutQuality

    public init(image: PhotoReference, quality: CutoutQuality) {
        self.image = image
        self.quality = quality
    }
}
