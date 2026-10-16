import Foundation
import Models
import Testing
import UIKit

@testable import Features

/// Garment pictures come through the `ImageProvider`, shrunk to the size shown and cached, so
/// real photos can replace the placeholders in later phases without touching the grid.
@MainActor
struct GarmentImageLoaderTests {
    /// Answers with one large PNG for every stored photo, and counts the calls.
    actor PhotoProvider: ImageProvider {
        let png: Data
        private(set) var calls = 0

        init(width: Int, height: Int) {
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: width, height: height), format: Self.oneToOne)
            png = renderer.pngData { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        private static var oneToOne: UIGraphicsImageRendererFormat {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }

        func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
            calls += 1
            switch reference {
            case .stored: return png
            case .sample: return nil
            case .noPhoto: throw .unavailable
            }
        }
    }

    @Test func aPhotoIsDownsampledToTheSizeAsked() async throws {
        let provider = PhotoProvider(width: 1_600, height: 1_200)
        let loader = GarmentImageLoader(provider: provider)
        let image = try #require(await loader.image(for: .stored("p-1"), maxPixelSize: 180))
        let cgImage = try #require(image.cgImage)
        #expect(max(cgImage.width, cgImage.height) == 180)
        #expect(cgImage.width == 180 && cgImage.height == 135)
    }

    @Test(.heavyMainActorWork) func aLoadedPhotoIsCached() async {
        let provider = PhotoProvider(width: 400, height: 400)
        let loader = GarmentImageLoader(provider: provider)
        _ = await loader.image(for: .stored("p-1"), maxPixelSize: 100)
        _ = await loader.image(for: .stored("p-1"), maxPixelSize: 100)
        #expect(await provider.calls == 1)
        // Another size is another picture.
        _ = await loader.image(for: .stored("p-1"), maxPixelSize: 200)
        #expect(await provider.calls == 2)
        #expect(loader.providerRequests == 2)
    }

    @Test func noPictureIsRememberedSoItIsNotAskedForAgain() async {
        let provider = PhotoProvider(width: 10, height: 10)
        let loader = GarmentImageLoader(provider: provider)
        #expect(await loader.image(for: .sample("navy-trousers"), maxPixelSize: 100) == nil)
        #expect(await loader.image(for: .sample("navy-trousers"), maxPixelSize: 100) == nil)
        #expect(await provider.calls == 1)
    }

    /// A provider that fails is asked again next time: only a picture that isn't there is
    /// remembered as missing.
    @Test func aFailedLoadIsAskedForAgain() async throws {
        let provider = FlakyProvider()
        let loader = GarmentImageLoader(provider: provider)
        #expect(await loader.image(for: .stored("p-1"), maxPixelSize: 50) == nil)
        #expect(!loader.isMissing(.stored("p-1"), maxPixelSize: 50))
        #expect(try #require(await loader.image(for: .stored("p-1"), maxPixelSize: 50)).cgImage != nil)
        #expect(await provider.calls == 2)
    }

    /// The pictures remembered as missing are bounded: when the list is full it starts over.
    @Test func theMissingListIsBounded() async {
        let provider = PhotoProvider(width: 10, height: 10)
        let loader = GarmentImageLoader(provider: provider, missingLimit: 2)
        for name in ["a", "b", "c"] {
            _ = await loader.image(for: .sample(name), maxPixelSize: 100)
        }
        #expect(!loader.isMissing(.sample("a"), maxPixelSize: 100))
        #expect(loader.isMissing(.sample("c"), maxPixelSize: 100))
    }

    /// Fails the first call, then answers with a small PNG.
    actor FlakyProvider: ImageProvider {
        private(set) var calls = 0
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
            calls += 1
            if calls == 1 { throw .unavailable }
            return png
        }
    }

    @Test func aPieceWithNoPhotoNeverAsks() async {
        let provider = PhotoProvider(width: 10, height: 10)
        let loader = GarmentImageLoader(provider: provider)
        #expect(await loader.image(for: .noPhoto, maxPixelSize: 100) == nil)
        #expect(await provider.calls == 0)
    }

    @Test func unreadableBytesGiveThePlaceholder() async {
        #expect(await GarmentImageLoader.downsample(Data("not an image".utf8), maxPixelSize: 100) == nil)
    }

    /// Stage A's fixture provider has no pictures, so every piece draws its placeholder.
    @Test func theStageAProviderHasNoPictures() async {
        let loader = GarmentImageLoader(provider: PlaceholderProviderStandIn())
        #expect(await loader.image(for: .sample("navy-trousers"), maxPixelSize: 100) == nil)
    }

    struct PlaceholderProviderStandIn: ImageProvider {
        func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? { nil }
    }
}

/// Every kind of piece has its own outline, and colours resolve for every family.
struct GarmentPlaceholderTests {
    @Test(arguments: GarmentCategory.allCases)
    func eachKindDrawsInsideItsFrame(_ category: GarmentCategory) {
        let rect = CGRect(x: 0, y: 0, width: 70, height: 90)
        let outline = GarmentSilhouette(category: category).path(in: rect).boundingRect
        let detail = GarmentDetail(category: category).path(in: rect).boundingRect
        #expect(!outline.isEmpty)
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(outline))
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(detail))
    }

    @Test func kindsHaveDifferentOutlines() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 128)
        let bounds = Set(
            GarmentCategory.allCases.map { "\(GarmentSilhouette(category: $0).path(in: rect).boundingRect)" })
        #expect(bounds.count == GarmentCategory.allCases.count)
    }

    /// Dark cloth gets a lighter outline so it still reads on the dark floor.
    @Test func lineColoursShowOnTheirFill() {
        for name in ColorName.allCases {
            let fill = GarmentColor.fill(for: name)
            #expect(abs(fill.line.luminance - fill.luminance) > 0.005, "\(name) has an invisible outline")
        }
    }

    @Test func everyColourHasAName() {
        #expect(Set(ColorName.allCases.map(\.title)).count == ColorName.allCases.count)
        #expect(Set(GarmentCategory.allCases.map(\.chipTitle)).count == GarmentCategory.allCases.count)
    }
}
