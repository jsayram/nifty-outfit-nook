import CoreGraphics
import Synchronization
import Testing

@testable import DesignSystem

/// Pictures to make stickers from, drawn in tests.
enum StickerTestArt {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// A transparent picture with a filled red rectangle `rect` inside it (origin bottom left).
    static func rectangle(_ rect: CGRect, canvas: CGSize) -> CGImage? {
        draw(canvas) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(rect)
        }
    }

    static func draw(_ canvas: CGSize, _ body: (CGContext) -> Void) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        body(context)
        return context.makeImage()
    }
}

/// Reads pixels of a rendered picture, rows from the top.
struct PixelReader {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: StickerTestArt.sRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    /// Red, green, blue (premultiplied) and alpha, 0 to 255.
    func pixel(_ x: Int, _ y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let index = (y * width + x) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    /// The most opaque pixel in rows `rows`.
    func maximumAlpha(rows: Range<Int>) -> UInt8 {
        var best: UInt8 = 0
        for y in rows {
            for x in 0..<width { best = max(best, pixel(x, y).alpha) }
        }
        return best
    }
}

/// The sticker's measurements grow with its size, as the mockups' edges do.
struct StickerSpecTests {
    @Test func theEdgeGrowsWithTheSticker() {
        let detail = StickerSpec(size: CGSize(width: 190, height: 236), scale: 3, appearance: .light)
        let closet = StickerSpec(size: CGSize(width: 70, height: 90), scale: 3, appearance: .light)
        let bundle = StickerSpec(size: CGSize(width: 44, height: 56), scale: 3, appearance: .light)
        #expect(detail.edgeWidth > closet.edgeWidth)
        #expect(abs(detail.edgeWidth - 4.248) < 0.001)
        #expect(abs(closet.edgeWidth - 1.62) < 0.001)
        #expect(bundle.edgeWidth == 1.25)
        #expect(StickerSpec(size: CGSize(width: 900, height: 900), scale: 2, appearance: .light).edgeWidth == 6)
    }

    /// The shadow sits further down than it spreads, so it shows below the sticker, not above.
    @Test func theShadowFallsFurtherThanItSpreads() {
        for side in [30.0, 60, 90, 150, 236, 400] {
            let spec = StickerSpec(size: CGSize(width: side, height: side), scale: 3, appearance: .light)
            #expect(spec.shadowOffset >= spec.shadowBlur)
            #expect(spec.bleed >= spec.shadowOffset + spec.shadowBlur)
        }
    }

    @Test func sizesRoundToHalfPoints() {
        let a = StickerSpec(size: CGSize(width: 70.1, height: 89.9), scale: 3, appearance: .light)
        let b = StickerSpec(size: CGSize(width: 70, height: 90), scale: 3, appearance: .light)
        #expect(a == b)
    }
}

/// The renderer: the edge follows the garment, the shadow falls below, and the result fits the
/// sticker's size.
struct StickerRendererTests {
    private let spec = StickerSpec(size: CGSize(width: 100, height: 100), scale: 2, appearance: .light)

    /// A 100 x 60 red block in a larger transparent picture: it's cropped, fitted and centred.
    private func block() throws -> (StickerArtwork, PixelReader) {
        let source = try #require(
            StickerTestArt.rectangle(
                CGRect(x: 50, y: 50, width: 100, height: 60), canvas: CGSize(width: 300, height: 200)))
        let artwork = try #require(StickerRenderer.render(source, spec: spec))
        return (artwork, try #require(PixelReader(artwork.image)))
    }

    @Test func thePictureIsTheStickerPlusRoomForTheShadow() throws {
        let (artwork, _) = try block()
        let bleed = spec.bleedPixels
        #expect(artwork.image.width == 200 + 2 * bleed)
        #expect(artwork.image.height == 200 + 2 * bleed)
        #expect(artwork.bleed == CGFloat(bleed) / 2)
        #expect(artwork.byteCount >= artwork.image.width * artwork.image.height * 4)
    }

    @Test func theGarmentKeepsItsColourAndGetsAWhiteEdge() throws {
        let (_, pixels) = try block()
        let middle = pixels.width / 2
        // The garment is fitted to the width inside the edge: 200 - 2 * edge pixels wide.
        let centre = pixels.pixel(middle, pixels.height / 2)
        #expect(centre.red == 255 && centre.green == 0 && centre.alpha == 255)
        // Just past the garment's left side, inside the edge: opaque white paper.
        let edge = spec.edgeWidth * spec.scale
        let garmentLeft = spec.bleedPixels + Int(edge.rounded(.up))
        let paper = pixels.pixel(garmentLeft - 2, pixels.height / 2)
        #expect(paper.alpha == 255 && paper.red == 255 && paper.green == 255 && paper.blue == 255)
        // Well past the edge on the left there's nothing.
        #expect(pixels.pixel(spec.bleedPixels - 4, pixels.height / 2).alpha < 30)
    }

    /// The edge follows the outline: a thin line gets as much paper beside it as a big shape.
    @Test func thinPartsGetTheFullEdge() throws {
        // A 2 pixel line across a 200 x 200 picture, at the sticker's own scale.
        let source = try #require(
            StickerTestArt.draw(CGSize(width: 200, height: 200)) { context in
                context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 99, width: 200, height: 2))
                context.fill(CGRect(x: 99, y: 0, width: 2, height: 200))
            })
        let artwork = try #require(StickerRenderer.render(source, spec: spec))
        let pixels = try #require(PixelReader(artwork.image))
        let edge = Int((spec.edgeWidth * spec.scale).rounded(.down))
        // Find the vertical line's column in the middle row of the top half, then step out.
        let y = spec.bleedPixels + 30
        // The line is the least red opaque pixel in the row: everything around it is white paper.
        let lineX = try #require(
            (0..<pixels.width).filter { pixels.pixel($0, y).alpha == 255 }
                .min { pixels.pixel($0, y).red < pixels.pixel($1, y).red })
        #expect(pixels.pixel(lineX, y).blue > 200)
        let beside = pixels.pixel(lineX - edge + 1, y)
        #expect(beside.alpha == 255 && beside.red == 255 && beside.blue == 255)
        #expect(pixels.pixel(lineX - edge - 3, y).alpha < 30)
    }

    /// Nothing shows above the sticker, and the shadow shows below it (soft style).
    @Test func theShadowIsOnlyBelow() throws {
        let (_, pixels) = try block()
        let bleed = spec.bleedPixels
        // The garment and its edge are 200 - 2 * edge wide and (60 / 100) of that tall, centred.
        let edge = spec.edgeWidth * spec.scale
        let garmentHeight = (200 - 2 * edge) * 0.6
        let paperTop = bleed + Int(((200 - garmentHeight) / 2 - edge).rounded(.down))
        let paperBottom = bleed + Int(((200 + garmentHeight) / 2 + edge).rounded(.up))
        #expect(pixels.maximumAlpha(rows: 0..<(paperTop - 2)) <= 3)
        #expect(pixels.maximumAlpha(rows: (paperBottom + 2)..<(paperBottom + 8)) > 10)
    }

    @Test func darkUsesTheDimmedPaper() throws {
        let dark = StickerSpec(size: spec.size, scale: spec.scale, appearance: .dark)
        let source = try #require(
            StickerTestArt.rectangle(
                CGRect(x: 50, y: 50, width: 100, height: 60), canvas: CGSize(width: 300, height: 200)))
        let artwork = try #require(StickerRenderer.render(source, spec: dark))
        let pixels = try #require(PixelReader(artwork.image))
        let edge = dark.edgeWidth * dark.scale
        let paper = pixels.pixel(dark.bleedPixels + Int(edge.rounded(.up)) - 2, pixels.height / 2)
        let expected = Palette.value(for: .stickerEdge).dark
        #expect(paper.alpha == 255)
        #expect(abs(Int(paper.red) - Int(expected.red)) <= 2)
        #expect(abs(Int(paper.blue) - Int(expected.blue)) <= 2)
    }

    /// A resting sticker sits on the bottom of its space; a centred one floats in the middle.
    @Test func aRestingStickerSitsOnTheBottom() throws {
        let source = try #require(
            StickerTestArt.rectangle(
                CGRect(x: 50, y: 50, width: 100, height: 60), canvas: CGSize(width: 300, height: 200)))
        let resting = StickerSpec(size: spec.size, scale: spec.scale, appearance: .light, placement: .resting)
        let restingSticker = try #require(StickerRenderer.render(source, spec: resting))
        let centredSticker = try #require(StickerRenderer.render(source, spec: spec))
        let restingPixels = try #require(PixelReader(restingSticker.image))
        let centredPixels = try #require(PixelReader(centredSticker.image))
        let bottomRow = spec.bleedPixels + spec.pixelHeight - 2
        let middle = restingPixels.width / 2
        #expect(restingPixels.pixel(middle, bottomRow).alpha == 255)
        #expect(centredPixels.pixel(middle, bottomRow).alpha < 255)
        #expect(restingPixels.pixel(middle, spec.bleedPixels + 30).alpha == 0)
    }

    @Test func anEmptyPictureMakesNoSticker() throws {
        let empty = try #require(StickerTestArt.draw(CGSize(width: 40, height: 40)) { _ in })
        #expect(StickerRenderer.render(empty, spec: spec) == nil)
    }

    @Test func opaqueBoundsFindTheGarment() throws {
        // Core Graphics draws from the bottom left; the bounds come back from the top left.
        let source = try #require(
            StickerTestArt.rectangle(
                CGRect(x: 10, y: 20, width: 30, height: 40), canvas: CGSize(width: 100, height: 100)))
        #expect(StickerRenderer.opaqueBounds(of: source) == CGRect(x: 10, y: 40, width: 30, height: 40))
    }
}

/// The cache makes each sticker once and keeps the most recently used within its budget.
@MainActor
struct StickerCacheTests {
    /// A drawn source that counts how often it's asked to draw.
    final class Counter: Sendable {
        private let value = Mutex(0)
        var count: Int { value.withLock { $0 } }
        func increment() { value.withLock { $0 += 1 } }
    }

    private func source(_ counter: Counter) -> StickerSource {
        .drawn { _ in
            counter.increment()
            return StickerTestArt.rectangle(
                CGRect(x: 2, y: 2, width: 16, height: 16), canvas: CGSize(width: 20, height: 20))
        }
    }

    private func key(_ id: String, side: CGFloat = 40, appearance: Appearance = .light) -> StickerCache.Key {
        StickerCache.Key(
            id: id, spec: StickerSpec(size: CGSize(width: side, height: side), scale: 1, appearance: appearance))
    }

    @Test func aStickerIsMadeOnce() async {
        let cache = StickerCache()
        let counter = Counter()
        let first = await cache.sticker(for: key("a"), from: source(counter))
        let second = await cache.sticker(for: key("a"), from: source(counter))
        #expect(first != nil && second != nil)
        #expect(cache.renderCount == 1)
        #expect(counter.count == 1)
        #expect(cache.cached(key("a")) != nil)
    }

    @Test func viewsAskingAtOnceShareOneRender() async {
        let cache = StickerCache()
        let counter = Counter()
        async let one = cache.sticker(for: key("a"), from: source(counter))
        async let two = cache.sticker(for: key("a"), from: source(counter))
        async let three = cache.sticker(for: key("a"), from: source(counter))
        let results = await [one, two, three]
        #expect(results.allSatisfy { $0 != nil })
        #expect(cache.renderCount == 1)
        #expect(counter.count == 1)
    }

    @Test func anotherSizeOrAppearanceIsAnotherSticker() async {
        let cache = StickerCache()
        let counter = Counter()
        _ = await cache.sticker(for: key("a"), from: source(counter))
        _ = await cache.sticker(for: key("a", side: 60), from: source(counter))
        _ = await cache.sticker(for: key("a", appearance: .dark), from: source(counter))
        #expect(cache.renderCount == 3)
        #expect(cache.count == 3)
    }

    @Test func aSourceWithNoPictureIsRemembered() async {
        let cache = StickerCache()
        let counter = Counter()
        let nothing = StickerSource.drawn { _ in
            counter.increment()
            return nil
        }
        #expect(await cache.sticker(for: key("none"), from: nothing) == nil)
        #expect(await cache.sticker(for: key("none"), from: nothing) == nil)
        #expect(counter.count == 1)
        #expect(cache.isMissing(key("none")))
    }

    @Test func theLeastRecentlyUsedGoFirst() async throws {
        let counter = Counter()
        let one = try #require(await StickerCache().sticker(for: key("probe"), from: source(counter)))
        // Room for three stickers.
        let cache = StickerCache(byteLimit: one.byteCount * 3)
        for id in ["a", "b", "c"] { _ = await cache.sticker(for: key(id), from: source(counter)) }
        _ = cache.cached(key("a"))  // "a" was just used, so "b" is now the oldest.
        _ = await cache.sticker(for: key("d"), from: source(counter))
        #expect(cache.count == 3)
        #expect(cache.cached(key("b")) == nil)
        #expect(cache.cached(key("a")) != nil)
        #expect(cache.cached(key("d")) != nil)
        #expect(cache.byteCount <= cache.byteLimit)
    }

    @Test func stillImagesAreMadeStraightAwayAndKept() {
        let cache = StickerCache()
        let counter = Counter()
        #expect(cache.stickerNow(for: key("a"), from: source(counter)) != nil)
        #expect(cache.stickerNow(for: key("a"), from: source(counter)) != nil)
        #expect(counter.count == 1)
    }

    @Test func removeAllEmptiesIt() async {
        let cache = StickerCache()
        let counter = Counter()
        _ = await cache.sticker(for: key("a"), from: source(counter))
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.byteCount == 0)
        _ = await cache.sticker(for: key("a"), from: source(counter))
        #expect(counter.count == 2)
    }
}
