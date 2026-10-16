import Foundation

/// How a garment's picture is shown (RD-07, Phase 8b): the piece cut out of its photo, the photo
/// itself in a rounded tile, or the drawing for pieces with no photo.
///
/// One rule for every screen, so a piece looks the same wherever it appears. Screens decide only
/// the presentation: a sticker with a white edge where looks and detail show it, standing on the
/// floor in the Closet grid.
public enum GarmentArtChoice: Hashable, Sendable {
    /// No photo: the drawing of its kind in its colours. It's drawn like a cutout, so it gets
    /// the sticker edge too.
    case drawing
    /// A clean cutout: the piece on transparency.
    case cutout(PhotoReference)
    /// The original photo in a rounded tile, because there's no cutout yet or it isn't clean.
    /// `concerns` says why, and is empty while there's no cutout.
    case photoTile(PhotoReference, concerns: [CutoutThresholds.Concern])

    /// Chooses for a piece's photo and cutout. A cutout is used only when every signal is inside
    /// `thresholds`; otherwise the photo shows in a tile, so a messy edge never gets a white
    /// outline around it.
    public init(photo: PhotoReference, cutout: GarmentCutout?, thresholds: CutoutThresholds = .current) {
        if case .noPhoto = photo {
            self = .drawing
            return
        }
        guard let cutout else {
            self = .photoTile(photo, concerns: [])
            return
        }
        let concerns = thresholds.concerns(with: cutout.quality)
        self = concerns.isEmpty ? .cutout(cutout.image) : .photoTile(photo, concerns: concerns)
    }

    /// Chooses for a garment.
    public init(_ garment: Garment, thresholds: CutoutThresholds = .current) {
        self.init(photo: garment.photo, cutout: garment.cutout, thresholds: thresholds)
    }

    /// True when the piece shows cut out (a cutout or a drawing), false for the photo tile.
    public var isCutOut: Bool {
        switch self {
        case .drawing, .cutout: true
        case .photoTile: false
        }
    }
}

extension CutoutThresholds {
    /// The limits the app uses. Phase 8a's proposal until the benchmark on Lily's iPhone 12
    /// settles them (`docs/cutout-feasibility.md`).
    public static let current = CutoutThresholds.proposed
}
