import CoreGraphics
import DesignSystem
import Fixtures
import Models
import NookTestSupport
import Testing

@testable import Features

/// The pieces behind garment stickers (Phase 8b): the drawings as cutout-like pictures, the
/// tile's framing, and the cache with a large closet.
struct GarmentDrawingTests {
    /// Every kind draws on transparency, cropped to the piece, at about the size asked.
    @Test(arguments: GarmentCategory.allCases)
    func eachKindDrawsACutout(_ category: GarmentCategory) throws {
        let image = try #require(
            GarmentDrawing.image(
                category: category, colors: [.navy, .white], appearance: .light, longSide: 300, lineWidth: 3))
        #expect(abs(max(image.width, image.height) - 300) <= 8)
        // The top corners are see-through, as in a real cutout, and most of it is the garment.
        let alpha = try #require(Self.alpha(of: image))
        #expect(alpha(0, 0) == 0)
        #expect(alpha(image.width - 1, 0) == 0)
        var solid = 0
        for y in 0..<image.height {
            for x in 0..<image.width where alpha(x, y) == 255 { solid += 1 }
        }
        #expect(Double(solid) / Double(image.width * image.height) > 0.3)
    }

    @Test func darkDimsTheColours() throws {
        func middle(_ appearance: Appearance) throws -> UInt8 {
            let image = try #require(
                GarmentDrawing.image(
                    category: .dress, colors: [.white], appearance: appearance, longSide: 100, lineWidth: 2))
            let pixels = try #require(Self.pixels(of: image))
            return pixels[(image.height / 2 * image.width + image.width / 2) * 4]
        }
        #expect(try middle(.light) > middle(.dark))
    }

    @Test func piecesWithTheSameKindAndColoursShareASticker() {
        #expect(
            GarmentDrawing.stickerID(category: .top, colors: [.navy])
                == GarmentDrawing.stickerID(category: .top, colors: [.navy]))
        #expect(
            GarmentDrawing.stickerID(category: .top, colors: [.navy, .white])
                != GarmentDrawing.stickerID(category: .top, colors: [.white, .navy]))
        #expect(
            GarmentDrawing.stickerID(category: .top, colors: [.navy])
                != GarmentDrawing.stickerID(category: .dress, colors: [.navy]))
    }

    static func pixels(of image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return ok ? bytes : nil
    }

    /// Alpha at a pixel, rows from the top.
    static func alpha(of image: CGImage) -> ((Int, Int) -> UInt8)? {
        guard let bytes = pixels(of: image) else { return nil }
        return { x, y in bytes[(y * image.width + x) * 4 + 3] }
    }
}

/// The tile shows the garment, in the tile's shape, never past the photo's edges.
struct TileFramingTests {
    private func aspect(_ crop: CGRect, photoAspect: CGFloat) -> CGFloat {
        crop.width * photoAspect / crop.height
    }

    @Test func withoutSignalsItTakesTheMiddle() {
        // A 3:4 photo in a 4:5 tile: full width, a band from the middle.
        let crop = TileFraming.crop(subject: nil, photoAspect: 0.75, tileAspect: 0.8)
        #expect(crop.minX == 0 && abs(crop.width - 1) < 0.0001)
        #expect(abs(aspect(crop, photoAspect: 0.75) - 0.8) < 0.0001)
        #expect(abs(crop.midY - 0.5) < 0.0001)
    }

    @Test func itFramesTheGarmentWithRoomAround() {
        let subject = CutoutBounds(x: 0.3, y: 0.2, width: 0.3, height: 0.4)
        let crop = TileFraming.crop(subject: subject, photoAspect: 0.75, tileAspect: 0.8)
        let garment = CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.4)
        #expect(crop.contains(garment))
        #expect(crop.width < 0.7)
        #expect(abs(aspect(crop, photoAspect: 0.75) - 0.8) < 0.0001)
        #expect(abs(crop.midX - garment.midX) < 0.0001 && abs(crop.midY - garment.midY) < 0.0001)
    }

    @Test func itStaysInsideThePhoto() {
        // A garment in the corner, and one taller than a wide tile allows.
        let corner = TileFraming.crop(
            subject: CutoutBounds(x: 0.8, y: 0.85, width: 0.2, height: 0.15), photoAspect: 0.75, tileAspect: 1)
        #expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.0001, dy: -0.0001).contains(corner))
        #expect(abs(aspect(corner, photoAspect: 0.75) - 1) < 0.0001)
        let tall = TileFraming.crop(
            subject: CutoutBounds(x: 0.1, y: 0, width: 0.8, height: 1), photoAspect: 0.75, tileAspect: 2)
        #expect(abs(tall.width - 1) < 0.0001)
        #expect(abs(aspect(tall, photoAspect: 0.75) - 2) < 0.0001)
    }

    @Test func croppingAnImageKeepsTheTileShape() throws {
        let photo = try #require(
            SyntheticGarmentPhotos.draw(.flatLayTee, width: 300, height: 400))
        let cropped = TileFraming.crop(
            photo, subject: CutoutBounds(x: 0.2, y: 0.2, width: 0.6, height: 0.5),
            tileSize: CGSize(width: 70, height: 90))
        #expect(abs(CGFloat(cropped.width) / CGFloat(cropped.height) - 70.0 / 90) < 0.02)
        #expect(cropped.width < 300)
    }
}

/// A closet of 2,400 pieces scrolled down and back up: each sticker is made once, however
/// often a cell shows it, and pieces that look the same share one.
@MainActor
struct GarmentStickerCacheTests {
    private static let cellSize = CGSize(width: 70, height: 90)

    private func cells() -> [(id: String, source: StickerSource)] {
        let data = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)
        return data.garments.filter(\.isInCloset).map {
            GarmentPicture.drawingSticker(category: $0.category, colors: $0.colors)
        }
    }

    /// Scale 1 keeps the test quick; the cache treats every scale the same way.
    private func key(_ id: String) -> StickerCache.Key {
        StickerCache.Key(id: id, spec: StickerSpec(size: Self.cellSize, scale: 1, appearance: .light))
    }

    /// Asks for every cell on screen, a row of three at a time, as the grid would while scrolling.
    private func scroll(_ cells: [(id: String, source: StickerSource)], rows: some Sequence<Int>, cache: StickerCache)
        async
    {
        let visibleRows = 7
        for row in rows {
            let first = row * 3
            let last = min(cells.count, first + visibleRows * 3)
            guard first < last else { continue }
            for cell in cells[first..<last] {
                _ = await cache.sticker(for: key(cell.id), from: cell.source)
            }
        }
    }

    @Test func scrollingTheLargeClosetMakesEachStickerOnce() async {
        let cells = cells()
        #expect(cells.count >= 2_000)
        let distinct = Set(cells.map(\.id)).count
        let cache = StickerCache(byteLimit: 512 << 20)
        let rowCount = (cells.count + 2) / 3
        await scroll(cells, rows: 0..<rowCount, cache: cache)
        #expect(cache.renderCount == distinct)
        // Pieces of the same kind and colours share a sticker, so far fewer are made than cells.
        #expect(distinct < cells.count / 2)
        // Back up to the top: nothing is made again.
        await scroll(cells, rows: (0..<rowCount).reversed(), cache: cache)
        #expect(cache.renderCount == distinct)
    }

    /// With a small budget the oldest stickers go, but the ones just scrolled past are still
    /// there when she scrolls back a little.
    @Test func aSmallBudgetKeepsWhatWasJustOnScreen() async throws {
        let cells = cells()
        let probe = try #require(
            await StickerCache().sticker(for: key(cells[0].id), from: cells[0].source))
        let cache = StickerCache(byteLimit: probe.byteCount * 120)
        await scroll(cells, rows: 0..<200, cache: cache)
        let made = cache.renderCount
        #expect(cache.byteCount <= cache.byteLimit)
        // Back up ten rows and down again.
        await scroll(cells, rows: (190..<200).reversed(), cache: cache)
        await scroll(cells, rows: 190..<200, cache: cache)
        #expect(cache.renderCount == made)
    }
}

/// Making a sticker is the slow part, and it runs once per sticker in the background. This
/// catches it getting many times slower.
struct StickerSpeedTests {
    @Test func aDetailSizedStickerAtThreeTimesScale() throws {
        let spec = StickerSpec(size: CGSize(width: 190, height: 236), scale: 3, appearance: .light)
        let sticker = GarmentPicture.drawingSticker(category: .dress, colors: [.blue, .white])
        var made: StickerArtwork?
        let elapsed = SpeedCheck.fastest {
            made = sticker.source.picture(for: spec).flatMap { StickerRenderer.render($0, spec: spec) }
        }
        #expect(made != nil)
        print("A detail-sized sticker at 3x took \(elapsed)")
        #expect(elapsed < SpeedCheck.limit(.milliseconds(250)), "A detail-sized sticker took \(elapsed)")
    }
}
