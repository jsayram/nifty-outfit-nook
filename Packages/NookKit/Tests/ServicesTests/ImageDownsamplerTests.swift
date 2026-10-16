import CoreGraphics
import Fixtures
import Foundation
import ImageIO
import Models
import Testing
import UniformTypeIdentifiers

@testable import Services

struct ImageDownsamplerTests {
    @Test func aBigPhotoShrinksToTheWorkingSize() throws {
        let photo = SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 3024, height: 4032)
        let image = try ImageDownsampler.image(from: photo, maxPixelSize: 1536, maxSourcePixels: 100_000_000)
        #expect(image.height == 1536)
        #expect(image.width == 1152)
    }

    @Test func aSmallPhotoIsNotEnlarged() throws {
        let photo = SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 400, height: 500)
        let image = try ImageDownsampler.image(from: photo, maxPixelSize: 1536, maxSourcePixels: 100_000_000)
        #expect(image.width == 400)
        #expect(image.height == 500)
    }

    /// Phone photos are often stored sideways with an orientation flag. The working image must
    /// be upright, or the mask and the sticker would come out turned.
    @Test func theOrientationFlagIsApplied() throws {
        let photo = try #require(Self.jpeg(.flatLayTee, width: 1200, height: 900, orientation: .right))
        let image = try ImageDownsampler.image(from: photo, maxPixelSize: 1536, maxSourcePixels: 100_000_000)
        #expect(image.width == 900)
        #expect(image.height == 1200)
    }

    @Test func theSafetyLimitCountsPixelsNotBytes() throws {
        let photo = SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 1000, height: 1000)
        #expect(throws: CutoutError.imageTooLarge) {
            try ImageDownsampler.image(from: photo, maxPixelSize: 256, maxSourcePixels: 999_999)
        }
        #expect(throws: Never.self) {
            try ImageDownsampler.image(from: photo, maxPixelSize: 256, maxSourcePixels: 1_000_000)
        }
    }

    @Test func truncatedDataIsUnreadable() {
        let photo = SyntheticGarmentPhotos.jpeg(.flatLayTee)
        #expect(throws: CutoutError.unreadableImage) {
            try ImageDownsampler.image(from: photo.prefix(64), maxPixelSize: 1536, maxSourcePixels: 100_000_000)
        }
    }

    /// A JPEG of the scene with an EXIF orientation flag.
    private static func jpeg(
        _ scene: SyntheticGarmentPhotos.Scene, width: Int, height: Int, orientation: CGImagePropertyOrientation
    ) -> Data? {
        let data = NSMutableData()
        guard let image = SyntheticGarmentPhotos.draw(scene, width: width, height: height),
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
