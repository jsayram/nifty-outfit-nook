import Accelerate
import CoreGraphics
import Foundation

/// Draws a garment as a sticker: the piece, a thick white edge that follows its outline, and a
/// soft shadow under it (RD-07, `.stk` in `results.html` and `garment.html`).
///
/// The input is any picture with transparency: a cutout from a photo, or a drawing. The steps:
///
/// 1. Crop to the part that isn't transparent, and fit it inside the sticker's size, leaving
///    room for the edge.
/// 2. Grow the garment's outline by the edge width: a greyscale dilation of its alpha with a
///    round brush (`vImageDilate_Planar8`), not a ring of offset copies. Every pixel within the
///    edge width of the garment becomes paper. The brush's rim is soft and the garment's own
///    anti-aliased edge carries through, so the paper's edge is smooth, also along slanted
///    sides. Thin straps get the same edge as the rest, and small holes (a bag's handle) fill
///    in, as on a die-cut sticker.
/// 3. Paint the grown outline in the paper colour (`stickerEdge`), with the shadow under it,
///    then draw the garment on top.
///
/// Core Graphics and Accelerate on the CPU, so the result is the same on every device and in
/// the snapshot tests. It's slow next to drawing a cached picture (about 25 ms for a
/// detail-sized sticker at 3x in a Debug build), so it never runs on the main
/// actor in the app: `StickerCache` makes each sticker once, in the background, and keeps it.
nonisolated public enum StickerRenderer {
    /// The sticker for `source` at `spec`, or `nil` when the source is empty (fully
    /// transparent) or the size is too small to draw.
    public static func render(_ source: CGImage, spec: StickerSpec) -> StickerArtwork? {
        guard let crop = opaqueBounds(of: source), let garment = source.cropping(to: crop) else { return nil }
        let edge = spec.edgeWidth * spec.scale
        let bleed = spec.bleedPixels
        let width = spec.pixelWidth + 2 * bleed
        let height = spec.pixelHeight + 2 * bleed
        let available = CGSize(
            width: CGFloat(spec.pixelWidth) - 2 * edge, height: CGFloat(spec.pixelHeight) - 2 * edge)
        guard available.width >= 1, available.height >= 1 else { return nil }

        // Fit the garment inside the edge, centred across the sticker's footprint, and centred
        // or resting on its bottom. Core Graphics puts the origin at the bottom left.
        let fit = min(available.width / CGFloat(garment.width), available.height / CGFloat(garment.height))
        let garmentSize = CGSize(width: CGFloat(garment.width) * fit, height: CGFloat(garment.height) * fit)
        let garmentRect = CGRect(
            x: CGFloat(bleed) + (CGFloat(spec.pixelWidth) - garmentSize.width) / 2,
            y: spec.placement == .resting
                ? CGFloat(bleed) + edge : CGFloat(bleed) + (CGFloat(spec.pixelHeight) - garmentSize.height) / 2,
            width: garmentSize.width, height: garmentSize.height)

        guard
            let mask = alphaMask(of: garment, in: garmentRect, width: width, height: height),
            let coverage = paperCoverage(mask, width: width, height: height, edge: edge),
            let paperMask = grayImage(coverage, width, height),
            let paper = paper(paperMask, width: width, height: height, appearance: spec.appearance),
            let context = rgbaContext(width: width, height: height)
        else { return nil }

        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let shadow = Palette.value(for: .shadow)[spec.appearance]
        context.setShadow(
            offset: CGSize(width: 0, height: -spec.shadowOffset * spec.scale),
            blur: spec.shadowBlur * spec.scale,
            color: CGColor(
                srgbRed: CGFloat(shadow.red) / 255, green: CGFloat(shadow.green) / 255,
                blue: CGFloat(shadow.blue) / 255,
                alpha: shadow.alpha * shadowStrength(spec.appearance)))
        context.draw(paper, in: full)
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.interpolationQuality = .high
        context.draw(garment, in: garmentRect)
        guard let image = context.makeImage() else { return nil }
        return StickerArtwork(image: image, spec: spec)
    }

    /// The mockups' sticker shadow is lighter than the soft style's plate shadow (16% against
    /// 26% in light), and a little lighter in dark too (45% against 55%), so these scale the
    /// `shadow` token down.
    static func shadowStrength(_ appearance: Appearance) -> Double {
        switch appearance {
        case .light: 0.7
        case .dark: 0.85
        }
    }

    // MARK: Steps

    /// The smallest rectangle holding every pixel that's more than faintly visible, in the
    /// picture's own pixels with the origin at the top left (as `CGImage.cropping(to:)` takes it).
    static func opaqueBounds(of image: CGImage, threshold: UInt8 = 12) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let context = alphaContext(width: width, height: height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        for y in 0..<height {
            let row = pixels + y * rowBytes
            var x = 0
            while x < width {
                if row[x] > threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
                x += 1
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The garment's alpha drawn where it will sit, one byte per pixel, rows from the top.
    static func alphaMask(of garment: CGImage, in rect: CGRect, width: Int, height: Int) -> [UInt8]? {
        guard let context = alphaContext(width: width, height: height), let data = context.data else { return nil }
        context.interpolationQuality = .high
        context.draw(garment, in: rect)
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var mask = [UInt8](repeating: 0, count: width * height)
        mask.withUnsafeMutableBufferPointer { out in
            guard let start = out.baseAddress else { return }
            for y in 0..<height {
                (start + y * width).update(from: pixels + y * rowBytes, count: width)
            }
        }
        return mask
    }

    /// How much of each pixel is paper, from 0 to 255: the garment's alpha grown by `edge`
    /// pixels with a round brush whose rim fades over one pixel. Each output pixel is the
    /// largest of the nearby garment pixels, less the brush's fade at that distance.
    ///
    /// The alpha is doubled first, so anything at least half covered counts as fully there: a
    /// thin strap whose pixels are only partly covered still gets solid paper around it, and the
    /// outer rim stays soft.
    static func paperCoverage(_ mask: [UInt8], width: Int, height: Int, edge: CGFloat) -> [UInt8]? {
        let brush = brush(edge: edge)
        var source = mask
        var coverage = [UInt8](repeating: 0, count: width * height)
        let error = source.withUnsafeMutableBytes { source in
            coverage.withUnsafeMutableBytes { coverage in
                var input = vImage_Buffer(
                    data: source.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width)
                var output = vImage_Buffer(
                    data: coverage.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width)
                let doubled = vImageTableLookUp_Planar8(&input, &input, doubling, vImage_Flags(kvImageNoFlags))
                guard doubled == kvImageNoError else { return doubled }
                return vImageDilate_Planar8(
                    &input, &output, 0, 0, brush.weights, vImagePixelCount(brush.side), vImagePixelCount(brush.side),
                    vImage_Flags(kvImageNoFlags))
            }
        }
        return error == kvImageNoError ? coverage : nil
    }

    /// Twice each value, at most 255.
    private static let doubling: [UInt8] = (0...255).map { UInt8(min(255, $0 * 2)) }

    /// The round brush for `edge` pixels: what's taken off a garment pixel at each offset. 0
    /// within `edge - 0.5`, rising to 255 (nothing) at `edge + 0.5`. Its side is odd.
    static func brush(edge: CGFloat) -> (weights: [UInt8], side: Int) {
        let reach = Int((edge + 0.5).rounded(.up))
        let side = 2 * reach + 1
        var weights = [UInt8](repeating: 255, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let distance = Double((x - reach) * (x - reach) + (y - reach) * (y - reach)).squareRoot()
                let fade = min(1, max(0, distance - (Double(edge) - 0.5)))
                weights[y * side + x] = UInt8((fade * 255).rounded())
            }
        }
        return (weights, side)
    }

    /// The paper: the grown outline filled with the `stickerEdge` colour.
    static func paper(_ mask: CGImage, width: Int, height: Int, appearance: Appearance) -> CGImage? {
        guard let context = rgbaContext(width: width, height: height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let colour = Palette.value(for: .stickerEdge)[appearance]
        context.clip(to: full, mask: mask)
        context.setFillColor(
            CGColor(
                srgbRed: CGFloat(colour.red) / 255, green: CGFloat(colour.green) / 255,
                blue: CGFloat(colour.blue) / 255,
                alpha: colour.alpha))
        context.fill(full)
        return context.makeImage()
    }

    // MARK: Contexts

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func rgbaContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func alphaContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
    }

    /// A one-channel picture of `bytes`, which Core Graphics takes as a clipping mask.
    private static func grayImage(_ bytes: [UInt8], _ width: Int, _ height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
