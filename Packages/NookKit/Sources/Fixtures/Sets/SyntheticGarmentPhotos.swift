import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Sample data is compiled only in Debug: Release builds ship none (Phase 20a).
#if DEBUG
    /// Garment-like pictures drawn with Core Graphics, for testing the cutout pipeline (Phase 8a)
    /// without real photos. They're flat shapes on plain or lightly textured backgrounds, so they
    /// show whether the pipeline works and roughly how fast, not how well Vision handles real
    /// clothes. That needs real photos on Lily's phone (`docs/cutout-feasibility.md`).
    ///
    /// Nothing here is downloaded. Every picture is drawn the same way on every run.
    public enum SyntheticGarmentPhotos {
        public enum Scene: String, CaseIterable, Hashable, Sendable {
            /// A navy tee on a linen bed cover.
            case flatLayTee = "flat-lay-tee"
            /// A near-black dress on a charcoal background.
            case darkOnDark = "dark-on-dark"
            /// A white shirt on an off-white background.
            case whiteOnWhite = "white-on-white"
            /// A striped sweater on wood.
            case stripedSweater = "striped-sweater"
            /// A satin skirt with highlights.
            case shinySkirt = "shiny-skirt"
            /// A dress hanging from a hanger on a wall.
            case hangerDress = "hanger-dress"
            /// Trousers that run off the bottom of the picture.
            case cutOffTrousers = "cut-off-trousers"
            /// A tee and a pair of shoes apart from each other.
            case teeAndShoes = "tee-and-shoes"
            /// Only the linen bed cover, nothing on it.
            case emptyBed = "empty-bed"
        }

        /// The picture as JPEG data. `size` is in pixels; the drawing scales to it. With
        /// `location`, the JPEG carries made-up GPS and camera metadata, like a phone photo.
        public static func jpeg(_ scene: Scene, width: Int = 1200, height: Int = 1500, location: Bool = false) -> Data {
            let data = NSMutableData()
            guard let image = draw(scene, width: width, height: height),
                let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return Data() }
            var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
            if location {
                properties[kCGImagePropertyGPSDictionary] = [
                    kCGImagePropertyGPSLatitude: 40.6892,
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 74.0445,
                    kCGImagePropertyGPSLongitudeRef: "W",
                ]
                properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFModel: "Test camera"]
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return Data() }
            return data as Data
        }

        /// The picture as a `CGImage`, or `nil` if Core Graphics can't make a canvas that size.
        /// Without `background`, only the garments are drawn, on transparency.
        public static func draw(_ scene: Scene, width: Int = 1200, height: Int = 1500, background: Bool = true)
            -> CGImage?
        {
            guard let canvas = Canvas(width: width, height: height) else { return nil }
            canvas.draw(scene, background: background)
            return canvas.context.makeImage()
        }

        /// The scene's garments alone on transparency, cropped to `crop` (fractions of the picture,
        /// origin top left), as a PNG: a stand-in for what the cutout step returns, since the
        /// simulator can't lift subjects (Phase 8b's sample photos).
        public static func cutoutPNG(
            _ scene: Scene, width: Int = 1200, height: Int = 1500,
            crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        ) -> Data {
            let pixels = CGRect(
                x: crop.minX * CGFloat(width), y: crop.minY * CGFloat(height), width: crop.width * CGFloat(width),
                height: crop.height * CGFloat(height)
            ).integral
            guard let whole = draw(scene, width: width, height: height, background: false),
                let image = whole.cropping(to: pixels)
            else { return Data() }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
            else { return Data() }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return Data() }
            return data as Data
        }

        static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Draws in a 1000 x 1250 design space with the origin at the top left, scaled to the real size.
    private final class Canvas {
        let context: CGContext
        private var seed: UInt64 = 0x5EED_CAFE
        private var drawsBackground = true

        init?(width: Int, height: Int) {
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: SyntheticGarmentPhotos.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            self.context = context
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: CGFloat(width) / 1000, y: -CGFloat(height) / 1250)
        }

        /// Draws `scene`. Without `background`, only the garments (and a hanger) are drawn, on
        /// transparency, the way a perfect cutout would come out.
        func draw(_ scene: SyntheticGarmentPhotos.Scene, background: Bool = true) {
            drawsBackground = background
            switch scene {
            case .flatLayTee:
                linen()
                fill(tee(in: CGRect(x: 200, y: 280, width: 600, height: 640)), rgb: (0.16, 0.24, 0.48))
            case .darkOnDark:
                plain(0.15, 0.15, 0.16)
                fill(dress(in: CGRect(x: 280, y: 180, width: 440, height: 880)), rgb: (0.07, 0.07, 0.08))
            case .whiteOnWhite:
                plain(0.93, 0.92, 0.90)
                fill(tee(in: CGRect(x: 200, y: 280, width: 600, height: 640)), rgb: (0.98, 0.98, 0.97))
            case .stripedSweater:
                wood()
                stripes(tee(in: CGRect(x: 180, y: 260, width: 640, height: 700)))
            case .shinySkirt:
                plain(0.55, 0.55, 0.57)
                satin(skirt(in: CGRect(x: 250, y: 330, width: 500, height: 600)))
            case .hangerDress:
                plain(0.82, 0.76, 0.70)
                hanger(at: CGPoint(x: 500, y: 150), width: 380)
                fill(dress(in: CGRect(x: 320, y: 230, width: 360, height: 820)), rgb: (0.55, 0.20, 0.25))
            case .cutOffTrousers:
                linen()
                fill(trousers(in: CGRect(x: 300, y: 300, width: 400, height: 1100)), rgb: (0.24, 0.22, 0.20))
            case .teeAndShoes:
                linen()
                fill(tee(in: CGRect(x: 120, y: 140, width: 470, height: 500)), rgb: (0.20, 0.45, 0.35))
                fill(
                    CGPath(
                        roundedRect: CGRect(x: 600, y: 800, width: 240, height: 110), cornerWidth: 50, cornerHeight: 50,
                        transform: nil), rgb: (0.45, 0.30, 0.20))
                fill(
                    CGPath(
                        roundedRect: CGRect(x: 600, y: 960, width: 240, height: 110), cornerWidth: 50, cornerHeight: 50,
                        transform: nil), rgb: (0.45, 0.30, 0.20))
            case .emptyBed:
                linen()
            }
        }

        // MARK: Backgrounds

        private func plain(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
            guard drawsBackground else { return }
            context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1250))
        }

        private func linen() {
            guard drawsBackground else { return }
            plain(0.86, 0.81, 0.73)
            for _ in 0..<3000 {
                let shade = 0.78 + 0.1 * unit()
                context.setFillColor(red: shade, green: shade - 0.05, blue: shade - 0.12, alpha: 1)
                context.fill(CGRect(x: 1000 * unit(), y: 1250 * unit(), width: 2 + 4 * unit(), height: 1.5))
            }
        }

        private func wood() {
            guard drawsBackground else { return }
            plain(0.60, 0.43, 0.28)
            for row in 0..<25 {
                let shade = 0.5 + 0.15 * unit()
                context.setFillColor(red: shade, green: shade * 0.72, blue: shade * 0.46, alpha: 1)
                context.fill(CGRect(x: 0, y: CGFloat(row) * 50, width: 1000, height: 46))
            }
        }

        // MARK: Garments

        private func tee(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            path.move(to: point(0.38, 0))
            path.addQuadCurve(to: point(0.62, 0), control: point(0.5, 0.08))
            path.addLine(to: point(0.85, 0.05))
            path.addLine(to: point(1, 0.3))
            path.addLine(to: point(0.82, 0.38))
            path.addLine(to: point(0.78, 0.3))
            path.addLine(to: point(0.78, 1))
            path.addLine(to: point(0.22, 1))
            path.addLine(to: point(0.22, 0.3))
            path.addLine(to: point(0.18, 0.38))
            path.addLine(to: point(0, 0.3))
            path.addLine(to: point(0.15, 0.05))
            path.closeSubpath()
            return path
        }

        private func dress(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            path.move(to: point(0.3, 0))
            path.addLine(to: point(0.38, 0))
            path.addQuadCurve(to: point(0.62, 0), control: point(0.5, 0.06))
            path.addLine(to: point(0.7, 0))
            path.addLine(to: point(0.75, 0.35))
            path.addLine(to: point(1, 1))
            path.addQuadCurve(to: point(0, 1), control: point(0.5, 1.04))
            path.addLine(to: point(0.25, 0.35))
            path.closeSubpath()
            return path
        }

        private func skirt(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            path.move(to: point(0.25, 0))
            path.addLine(to: point(0.75, 0))
            path.addLine(to: point(1, 1))
            path.addQuadCurve(to: point(0, 1), control: point(0.5, 1.06))
            path.closeSubpath()
            return path
        }

        private func trousers(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            path.move(to: point(0.05, 0))
            path.addLine(to: point(0.95, 0))
            path.addLine(to: point(1, 1))
            path.addLine(to: point(0.56, 1))
            path.addLine(to: point(0.5, 0.3))
            path.addLine(to: point(0.44, 1))
            path.addLine(to: point(0, 1))
            path.closeSubpath()
            return path
        }

        private func hanger(at hook: CGPoint, width: CGFloat) {
            let path = CGMutablePath()
            path.addArc(
                center: CGPoint(x: hook.x, y: hook.y - 40), radius: 22, startAngle: .pi, endAngle: .pi * 2.4,
                clockwise: false)
            path.move(to: hook)
            path.addLine(to: CGPoint(x: hook.x - width / 2, y: hook.y + 90))
            path.addLine(to: CGPoint(x: hook.x + width / 2, y: hook.y + 90))
            path.closeSubpath()
            context.setStrokeColor(red: 0.35, green: 0.25, blue: 0.15, alpha: 1)
            context.setLineWidth(12)
            context.addPath(path)
            context.strokePath()
        }

        // MARK: Fills

        private func fill(_ path: CGPath, rgb: (CGFloat, CGFloat, CGFloat)) {
            context.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            context.addPath(path)
            context.fillPath()
        }

        private func stripes(_ path: CGPath) {
            context.saveGState()
            context.addPath(path)
            context.clip()
            for row in 0..<40 {
                let red = row.isMultiple(of: 2)
                context.setFillColor(
                    red: red ? 0.72 : 0.95, green: red ? 0.16 : 0.91, blue: red ? 0.20 : 0.82, alpha: 1)
                context.fill(CGRect(x: 0, y: CGFloat(row) * 32, width: 1000, height: 32))
            }
            context.restoreGState()
        }

        private func satin(_ path: CGPath) {
            context.saveGState()
            context.addPath(path)
            context.clip()
            let colors = [
                CGColor(srgbRed: 0.45, green: 0.30, blue: 0.55, alpha: 1),
                CGColor(srgbRed: 0.92, green: 0.85, blue: 0.95, alpha: 1),
                CGColor(srgbRed: 0.40, green: 0.25, blue: 0.50, alpha: 1),
                CGColor(srgbRed: 0.85, green: 0.78, blue: 0.90, alpha: 1),
                CGColor(srgbRed: 0.35, green: 0.22, blue: 0.45, alpha: 1),
            ]
            if let gradient = CGGradient(
                colorsSpace: SyntheticGarmentPhotos.sRGB, colors: colors as CFArray, locations: [0, 0.3, 0.5, 0.7, 1])
            {
                context.drawLinearGradient(
                    gradient, start: CGPoint(x: 250, y: 0), end: CGPoint(x: 750, y: 0), options: [])
            }
            context.restoreGState()
        }

        /// A fixed sequence in 0..<1, so every run draws the same texture.
        private func unit() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 11) / CGFloat(1 << 53)
        }
    }
#endif
