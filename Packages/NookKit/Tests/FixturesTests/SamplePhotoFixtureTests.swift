import CoreGraphics
import Foundation
import ImageIO
import Models
import NookTestSupport
import Testing

@testable import Fixtures

/// `-fixtures demo:photos=samples` (Phase 8b): drawn sample photos with stand-in cutouts, so the
/// sticker and the tile fallback show in the app without real photos.
struct SamplePhotoFixtureTests {
    @Test func theOptionIsRead() {
        let configuration = FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:photos=samples:offline"])
        #expect(configuration == FixtureConfiguration(set: .demo, behavior: .offline, photos: .samples))
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:photos=nope"]).photos == .drawn)
        #expect(FixtureConfiguration(launchArguments: []).photos == .drawn)
    }

    /// Six clean cutouts become stickers; the fuzzy white tee and the tee with shoes fall back.
    @Test func sixAreStickersAndTwoAreTiles() {
        let garments = SamplePhotoGarments.garments(now: TestTime.now)
        #expect(garments.count == 8)
        let tiles = garments.filter { !GarmentArtChoice($0).isCutOut }
        #expect(Set(tiles.map(\.id)) == ["g-photo-white-on-white", "g-photo-tee-and-shoes"])
        let whiteTee = garments.first { $0.id == "g-photo-white-on-white" }
        #expect(
            whiteTee.map { GarmentArtChoice($0) }
                == .photoTile(
                    SamplePhotoGarments.photo(.whiteOnWhite), concerns: [.unsureEdges]))
    }

    @Test func signalsAreReadFromTheDrawing() throws {
        let trousers = try #require(
            SamplePhotoGarments.garments(now: TestTime.now).first { $0.id == "g-photo-cut-off-trousers" }?.cutout)
        // The trousers run off the bottom of the photo, and only the bottom.
        #expect(trousers.quality.touchedEdges == [.bottom])
        let tee = SamplePhotoGarments.measure(.flatLayTee)
        #expect(tee.edges.isEmpty)
        #expect(tee.coverage > 0.1 && tee.coverage < 0.4)
        #expect(abs(tee.bounds.x - 0.2) < 0.02 && abs(tee.bounds.width - 0.6) < 0.02)
    }

    @Test func theServicesAddThePiecesAndDrawTheirPictures() async throws {
        let services = FixtureServices.make(
            set: .demo, photos: .samples, now: TestTime.now, calendar: TestTime.calendar)
        let garments = try await services.closet.garments()
        let plain = try await FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
            .closet.garments()
        #expect(garments.count == plain.count + 8)

        let photo = try #require(
            try await services.images.imageData(for: SamplePhotoGarments.photo(.flatLayTee), maxPixelSize: 300))
        let cutout = try #require(
            try await services.images.imageData(for: SamplePhotoGarments.cutout(.flatLayTee), maxPixelSize: 300))
        #expect(try properties(of: photo).type == "public.jpeg")
        let png = try properties(of: cutout)
        #expect(png.type == "public.png")
        #expect(png.hasAlpha)
        // Cropped to the tee, which covers 60% of the photo's width.
        #expect(png.width < 240 && png.height < 300)
        #expect(png.width > 140)
        // Everything else keeps its drawing.
        #expect(try await services.images.imageData(for: .sample("navy-trousers"), maxPixelSize: 300) == nil)
        #expect(try await services.images.imageData(for: .sample("photo:nothing"), maxPixelSize: 300) == nil)
    }

    @Test func withoutTheOptionThereAreNoPictures() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        #expect(
            try await services.images.imageData(for: SamplePhotoGarments.photo(.flatLayTee), maxPixelSize: 300) == nil)
    }

    private func properties(of data: Data) throws -> (type: String, width: Int, height: Int, hasAlpha: Bool) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source)) as String
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let alpha = image.alphaInfo
        return (type, image.width, image.height, alpha != .none && alpha != .noneSkipLast && alpha != .noneSkipFirst)
    }
}
