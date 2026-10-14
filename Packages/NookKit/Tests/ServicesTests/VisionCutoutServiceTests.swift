import CoreGraphics
import Fixtures
import Foundation
import ImageIO
import Models
import Testing
import Vision

@testable import Services

/// The Vision cutout pipeline, end to end, on drawn garments.
///
/// Vision's foreground mask can't run on the iOS simulator, so the tests that need a real
/// cutout skip themselves there (`VisionSupport`) and run on a device. The rest run everywhere.
struct VisionCutoutServiceTests {
    private let service = VisionCutoutService()

    // MARK: Everywhere

    @Test func unreadableDataIsRefused() async {
        await #expect(throws: CutoutError.unreadableImage) {
            try await service.cutout(from: Data("not a picture".utf8))
        }
        await #expect(throws: CutoutError.unreadableImage) {
            try await service.cutout(from: Data())
        }
    }

    @Test func aPictureOverTheSafetyLimitIsRefusedBeforeDecoding() async {
        let small = VisionCutoutService(options: .init(maxPixelSize: 512, maxSourcePixels: 1_000_000))
        await #expect(throws: CutoutError.imageTooLarge) {
            try await small.cutout(from: SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 1200, height: 1500))
        }
    }

    @Test func aCancelledTaskStopsBeforeVision() async {
        let data = SyntheticGarmentPhotos.jpeg(.flatLayTee)
        let task = Task { () async throws(CutoutError) -> CutoutResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.cutout(from: data)
        }
        await #expect(throws: CutoutError.cancelled) { try await task.value }
    }

    /// On the simulator the service must say "unsupported", not "failed", so a screen can tell
    /// a missing feature from a bad photo.
    @Test func theSimulatorReportsUnsupported() async throws {
        #if targetEnvironment(simulator)
            let available = await VisionSupport.isAvailable
            try #require(!available, "Vision now runs on this simulator; this test can go.")
            await #expect(throws: CutoutError.unsupported) {
                try await service.cutout(from: SyntheticGarmentPhotos.jpeg(.flatLayTee))
            }
        #endif
    }

    @Test func visionErrorsMapToCasesAScreenCanUse() {
        func error(_ code: VNErrorCode) -> NSError { NSError(domain: VNErrorDomain, code: code.rawValue) }
        #expect(VisionCutoutService.cutoutError(for: error(.requestCancelled)) == .cancelled)
        #expect(VisionCutoutService.cutoutError(for: error(.unsupportedRequest)) == .unsupported)
        #expect(VisionCutoutService.cutoutError(for: error(.invalidImage)) == .unreadableImage)
        #expect(VisionCutoutService.cutoutError(for: CancellationError()) == .failed)
        #expect(VisionCutoutService.cutoutError(for: NSError(domain: "elsewhere", code: 1)) == .failed)
    }

    // MARK: Where Vision runs

    @Test(.enabled(VisionSupport.skipReason) { await VisionSupport.isAvailable })
    func aFlatLayTeeComesOutAsACleanSticker() async throws {
        let result = try await service.cutout(from: SyntheticGarmentPhotos.jpeg(.flatLayTee))
        let quality = result.quality
        #expect(quality.instanceCount == 1)
        #expect((0.1...0.4).contains(quality.coverage), "coverage \(quality.coverage)")
        #expect(quality.touchedEdges.isEmpty)
        #expect(CutoutThresholds.proposed.suggestsSticker(quality))

        let image = try #require(Self.image(from: result.imageData))
        #expect(image.width == result.pixelWidth && image.height == result.pixelHeight)
        // Cropped to the tee: smaller than the 1,200 x 1,500 photo, and the corners are clear.
        #expect(image.width < 1200 && image.height < 1500)
        let pixels = try #require(Self.alpha(of: image))
        #expect(pixels.corner == 0)
        #expect(pixels.center == 255)
    }

    @Test(.enabled(VisionSupport.skipReason) { await VisionSupport.isAvailable })
    func aBigPhotoIsWorkedOnAtTheWorkingSize() async throws {
        let photo = SyntheticGarmentPhotos.jpeg(.darkOnDark, width: 3024, height: 4032)
        let result = try await service.cutout(from: photo)
        // The subject can't be larger than the working size.
        #expect(max(result.pixelWidth, result.pixelHeight) <= VisionCutoutService.Options.standard.maxPixelSize)
    }

    @Test(.enabled(VisionSupport.skipReason) { await VisionSupport.isAvailable })
    func theCutoutCarriesNoMetadataFromThePhoto() async throws {
        let photo = SyntheticGarmentPhotos.jpeg(.flatLayTee, location: true)
        #expect(Self.properties(of: photo)?[kCGImagePropertyGPSDictionary] != nil)
        let result = try await service.cutout(from: photo)
        let properties = try #require(Self.properties(of: result.imageData))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyExifDictionary] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
    }

    @Test(.enabled(VisionSupport.skipReason) { await VisionSupport.isAvailable })
    func trousersRunningOffThePhotoTouchTheBottom() async throws {
        let result = try await service.cutout(from: SyntheticGarmentPhotos.jpeg(.cutOffTrousers))
        #expect(result.quality.touchedEdges.contains(.bottom))
        #expect(!result.quality.touchedEdges.contains(.top))
    }

    @Test(.enabled(VisionSupport.skipReason) { await VisionSupport.isAvailable })
    func anEmptyBedHasNoSubject() async {
        await #expect(throws: CutoutError.noSubject) {
            try await service.cutout(from: SyntheticGarmentPhotos.jpeg(.emptyBed))
        }
    }

    // MARK: Helpers

    private static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// The alpha at the top-left corner and at the centre.
    private static func alpha(of image: CGImage) -> (corner: UInt8, center: UInt8)? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return (bytes[3], bytes[((height / 2) * width + width / 2) * 4 + 3])
    }
}
