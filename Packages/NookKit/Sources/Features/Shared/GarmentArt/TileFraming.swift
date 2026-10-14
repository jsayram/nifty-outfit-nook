import CoreGraphics
import Models

/// Which part of a photo a tile shows (Phase 8b). A tile is a fixed shape and photos aren't, so
/// it crops. With the cutout step's `subjectBounds` it frames the garment with a little room
/// around it; without them it takes the middle of the photo.
nonisolated enum TileFraming {
    /// Room left around the garment, as a share of its size on each side.
    static let margin: CGFloat = 0.12

    /// The crop, as fractions of the photo with the origin at the top left, that fills a tile of
    /// `tileAspect` (width over height) from a photo of `photoAspect`.
    static func crop(subject: CutoutBounds?, photoAspect: CGFloat, tileAspect: CGFloat) -> CGRect {
        guard photoAspect > 0, tileAspect > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        // Work in a space where the photo is `photoAspect` wide and 1 high, so aspects are real.
        let wanted: CGRect
        if let subject, subject.width > 0, subject.height > 0 {
            let rect = CGRect(
                x: subject.x * photoAspect, y: subject.y, width: subject.width * photoAspect, height: subject.height)
            wanted = rect.insetBy(dx: -rect.width * margin, dy: -rect.height * margin)
        } else {
            wanted = CGRect(x: 0, y: 0, width: photoAspect, height: 1)
        }
        // Grow the short way to the tile's shape, around the subject's centre.
        var size = wanted.size
        if size.width / size.height < tileAspect {
            size.width = size.height * tileAspect
        } else {
            size.height = size.width / tileAspect
        }
        // Never more than the photo has: shrink to fit, keeping the tile's shape.
        let shrink = min(1, photoAspect / size.width, 1 / size.height)
        size = CGSize(width: size.width * shrink, height: size.height * shrink)
        let x = min(max(0, wanted.midX - size.width / 2), photoAspect - size.width)
        let y = min(max(0, wanted.midY - size.height / 2), 1 - size.height)
        return CGRect(x: x / photoAspect, y: y, width: size.width / photoAspect, height: size.height)
    }

    /// `image` cropped for a tile of `tileSize`.
    static func crop(_ image: CGImage, subject: CutoutBounds?, tileSize: CGSize) -> CGImage {
        guard image.width > 0, image.height > 0, tileSize.width > 0, tileSize.height > 0 else { return image }
        let unit = crop(
            subject: subject, photoAspect: CGFloat(image.width) / CGFloat(image.height),
            tileAspect: tileSize.width / tileSize.height)
        let pixels = CGRect(
            x: unit.minX * CGFloat(image.width), y: unit.minY * CGFloat(image.height),
            width: unit.width * CGFloat(image.width), height: unit.height * CGFloat(image.height)
        ).integral
        return image.cropping(to: pixels) ?? image
    }
}
