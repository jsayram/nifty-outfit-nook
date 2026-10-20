import CoreGraphics
import DesignSystem
import Models

/// The placeholder drawing (`GarmentPlaceholderArt`) as a picture on transparency, cropped to
/// the piece, the way a cutout from a photo comes out. So a piece with no photo, which is every
/// piece in Stage A, gets the same sticker edge a real cutout gets (Phase 8b).
///
/// Drawn with Core Graphics so it can run away from the main actor, from the same outlines and
/// colours as the SwiftUI drawing.
nonisolated enum GarmentDrawing {
    /// Names the drawing for the sticker cache. Pieces with the same kind and colours draw the
    /// same, so they share one sticker.
    static func stickerID(category: GarmentCategory, colors: [ColorName]) -> String {
        "drawing:\(category.rawValue):\(colors.map(\.rawValue).joined(separator: ","))"
    }

    /// The drawing about `longSide` pixels on its longer side, with outlines `lineWidth` pixels
    /// wide (the SwiftUI drawing's 1.6 points at the screen's scale).
    static func image(
        category: GarmentCategory, colors: [ColorName], appearance: Appearance, longSide: CGFloat, lineWidth: CGFloat
    ) -> CGImage? {
        let design = CGRect(origin: .zero, size: GarmentSilhouette.designSize)
        let outline = GarmentSilhouette(category: category).path(in: design)
        let detail = GarmentDetail(category: category).path(in: design)
        let scale = longSide / max(outline.boundingRect.width, outline.boundingRect.height)
        guard scale.isFinite, scale > 0 else { return nil }
        // Room for the half of the outline stroke that falls outside the shape.
        let bounds = outline.boundingRect.insetBy(dx: -lineWidth / scale, dy: -lineWidth / scale)
        let width = Int((bounds.width * scale).rounded(.up))
        let height = Int((bounds.height * scale).rounded(.up))
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Draw in the design box's coordinates, top left origin.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)

        let main = colors.first.map(GarmentColor.fill(for:)) ?? .unknown
        let second = colors.dropFirst().first.map(GarmentColor.fill(for:)) ?? main.scaled(0.86)
        if colors.first == .multicolor {
            context.saveGState()
            context.addPath(outline.cgPath)
            context.clip()
            let stripes = GarmentColor.multicolorStripes
            let band = design.height / CGFloat(stripes.count)
            for (index, stripe) in stripes.enumerated() {
                context.setFillColor(stripe.cgColor(in: appearance))
                context.fill(CGRect(x: design.minX, y: CGFloat(index) * band, width: design.width, height: band))
            }
            context.restoreGState()
        } else {
            context.addPath(outline.cgPath)
            context.setFillColor(main.cgColor(in: appearance))
            context.fillPath()
        }
        context.addPath(detail.cgPath)
        context.setFillColor(second.cgColor(in: appearance))
        context.fillPath()
        context.addPath(outline.cgPath)
        context.setStrokeColor(main.line.cgColor(in: appearance))
        context.setLineWidth(lineWidth / scale)
        context.setLineJoin(.round)
        context.strokePath()
        return context.makeImage()
    }

    /// The drawing for a sticker of `spec`, drawn at the sticker's own resolution.
    static func image(category: GarmentCategory, colors: [ColorName], for spec: StickerSpec) -> CGImage? {
        image(
            category: category, colors: colors, appearance: spec.appearance, longSide: spec.longSide * spec.scale,
            lineWidth: 1.6 * spec.scale)
    }
}

nonisolated extension GarmentColor {
    /// The colour in an appearance, for Core Graphics: real colours in light, dimmed to 92% in dark,
    /// as `color(in:)` does for SwiftUI.
    nonisolated func cgColor(in appearance: Appearance) -> CGColor {
        let factor = appearance == .dark ? 0.92 : 1
        return CGColor(srgbRed: red * factor, green: green * factor, blue: blue * factor, alpha: 1)
    }
}
