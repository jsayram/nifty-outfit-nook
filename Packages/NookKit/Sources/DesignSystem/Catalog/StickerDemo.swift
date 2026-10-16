#if DEBUG
    import CoreGraphics
    import SwiftUI

    /// Stickers and the photo tile fallback (Phase 8b), on the floor colour where they'll sit.
    /// The pictures are drawn here, since DesignSystem has no garments of its own.
    struct StickerDemo: View {
        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                CatalogCaption("Sticker: detail size, closet size, bundle size")
                HStack(alignment: .bottom, spacing: NookSpacing.large) {
                    NookSticker(
                        "catalog.tee", size: CGSize(width: 150, height: 180), source: .drawn(CatalogStickerArt.tee))
                    NookSticker(
                        "catalog.bag", size: CGSize(width: 70, height: 90), source: .drawn(CatalogStickerArt.bag))
                    NookSticker(
                        "catalog.skirt", size: CGSize(width: 44, height: 56), source: .drawn(CatalogStickerArt.skirt))
                }
                .padding(NookSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.nook.floor, in: NookRadius.shape(NookRadius.group))
                CatalogCaption("Fallback: the photo in a rounded tile, same space as the sticker")
                HStack(alignment: .bottom, spacing: NookSpacing.large) {
                    NookPhotoTile(CatalogStickerArt.photo, size: CGSize(width: 150, height: 180))
                    NookPhotoTile(CatalogStickerArt.photo, size: CGSize(width: 70, height: 90))
                    NookPhotoTile(nil, size: CGSize(width: 44, height: 56))
                }
                .padding(NookSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.nook.floor, in: NookRadius.shape(NookRadius.group))
                CatalogCaption("Thin parts keep the full edge: a strap and a hoop")
                NookSticker(
                    "catalog.thin", size: CGSize(width: 150, height: 110), source: .drawn(CatalogStickerArt.thinParts)
                )
                .padding(NookSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.nook.floor, in: NookRadius.shape(NookRadius.group))
            }
        }
    }

    /// Simple garment-like pictures on transparency, and a photo-like picture, for the catalog.
    nonisolated enum CatalogStickerArt {
        static func tee(_ spec: StickerSpec) -> CGImage? {
            draw(width: 300, height: 320) { context in
                let path = CGMutablePath()
                path.addLines(between: [
                    CGPoint(x: 110, y: 310), CGPoint(x: 190, y: 310), CGPoint(x: 245, y: 290), CGPoint(x: 300, y: 215),
                    CGPoint(x: 255, y: 185), CGPoint(x: 235, y: 215), CGPoint(x: 235, y: 10), CGPoint(x: 65, y: 10),
                    CGPoint(x: 65, y: 215), CGPoint(x: 45, y: 185), CGPoint(x: 0, y: 215), CGPoint(x: 55, y: 290),
                ])
                path.closeSubpath()
                fill(context, path, 0.36, 0.55, 0.42, dimmed: spec.appearance == .dark)
            }
        }

        static func bag(_ spec: StickerSpec) -> CGImage? {
            draw(width: 200, height: 220) { context in
                let body = CGPath(
                    roundedRect: CGRect(x: 10, y: 10, width: 180, height: 130), cornerWidth: 26, cornerHeight: 26,
                    transform: nil)
                fill(context, body, 0.48, 0.14, 0.22, dimmed: spec.appearance == .dark)
                context.setLineWidth(12)
                context.addArc(
                    center: CGPoint(x: 100, y: 140), radius: 60, startAngle: 0, endAngle: .pi, clockwise: false)
                context.replacePathWithStrokedPath()
                fill(context, context.path ?? CGMutablePath(), 0.48, 0.14, 0.22, dimmed: spec.appearance == .dark)
            }
        }

        static func skirt(_ spec: StickerSpec) -> CGImage? {
            draw(width: 200, height: 220) { context in
                let path = CGMutablePath()
                path.addLines(between: [
                    CGPoint(x: 55, y: 210), CGPoint(x: 145, y: 210), CGPoint(x: 195, y: 10), CGPoint(x: 5, y: 10),
                ])
                path.closeSubpath()
                fill(context, path, 0.18, 0.18, 0.2, dimmed: spec.appearance == .dark)
            }
        }

        /// A sandal-like shape with a thin strap and a small hoop, to show the edge on thin parts.
        static func thinParts(_ spec: StickerSpec) -> CGImage? {
            draw(width: 300, height: 200) { context in
                let sole = CGPath(
                    roundedRect: CGRect(x: 10, y: 10, width: 280, height: 40), cornerWidth: 20, cornerHeight: 20,
                    transform: nil)
                fill(context, sole, 0.77, 0.6, 0.42, dimmed: spec.appearance == .dark)
                context.setLineWidth(5)
                context.move(to: CGPoint(x: 60, y: 45))
                context.addCurve(
                    to: CGPoint(x: 240, y: 45), control1: CGPoint(x: 90, y: 180), control2: CGPoint(x: 210, y: 180))
                context.replacePathWithStrokedPath()
                fill(context, context.path ?? CGMutablePath(), 0.77, 0.6, 0.42, dimmed: spec.appearance == .dark)
                context.setLineWidth(4)
                context.addEllipse(in: CGRect(x: 132, y: 150, width: 36, height: 36))
                context.replacePathWithStrokedPath()
                fill(context, context.path ?? CGMutablePath(), 0.77, 0.6, 0.42, dimmed: spec.appearance == .dark)
            }
        }

        /// A photo-like picture: a garment on a linen background, edge to edge.
        static let photo: CGImage? = draw(width: 300, height: 360) { context in
            context.setFillColor(CGColor(srgbRed: 0.86, green: 0.81, blue: 0.73, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 360))
            context.setFillColor(CGColor(srgbRed: 0.8, green: 0.74, blue: 0.66, alpha: 1))
            for row in stride(from: 0, to: 360, by: 12) {
                context.fill(CGRect(x: 0, y: row, width: 300, height: 3))
            }
            let path = CGMutablePath()
            path.addLines(between: [
                CGPoint(x: 100, y: 300), CGPoint(x: 200, y: 300), CGPoint(x: 260, y: 40), CGPoint(x: 40, y: 40),
            ])
            path.closeSubpath()
            fill(context, path, 0.95, 0.95, 0.93, dimmed: false)
        }

        private static func fill(
            _ context: CGContext, _ path: CGPath, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, dimmed: Bool
        ) {
            let factor: CGFloat = dimmed ? 0.92 : 1
            context.beginPath()
            context.addPath(path)
            context.setFillColor(
                CGColor(srgbRed: red * factor, green: green * factor, blue: blue * factor, alpha: 1))
            context.fillPath()
        }

        private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
            guard let context = StickerRenderer.rgbaContext(width: width, height: height) else { return nil }
            body(context)
            return context.makeImage()
        }
    }
#endif
