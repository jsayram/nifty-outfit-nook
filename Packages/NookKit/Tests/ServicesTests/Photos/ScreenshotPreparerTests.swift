import CoreGraphics
import Foundation
import ImageIO
import Models
import NookTestSupport
import Testing
import UniformTypeIdentifiers

@testable import Services

/// The screenshot she attaches to a note (Phase 24d) leaves her phone as a clean, small JPEG: no
/// location, camera, time or caption, whatever the picker handed over (SECURITY_STANDARD §4).
struct ScreenshotPreparerTests {
    static let formats: [UTType] = [.jpeg, .png]

    @Test(arguments: formats)
    func whatLeavesHasNoMetadata(_ type: UTType) async throws {
        let photo = try #require(PhotoWithMetadata.make(type))
        // The test picture really carries a place, a camera and planted text.
        #expect(!PhotoWithMetadata.plantedTextFound(in: photo).isEmpty)
        #expect(!DirtyPhoto.metadataDictionaries(in: photo).isEmpty)

        let screenshot = try await ScreenshotPreparer().prepare(photo)
        #expect(DirtyPhoto.metadataDictionaries(in: screenshot.data).isEmpty)
        #expect(PhotoWithMetadata.plantedTextFound(in: screenshot.data).isEmpty)
        let properties = try #require(PhotoWithMetadata.properties(of: screenshot.data))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyIPTCDictionary] == nil)
        #expect(
            properties[kCGImagePropertyExifDictionary].flatMap { $0 as? [CFString: Any] }?[
                kCGImagePropertyExifUserComment] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil && tiff[kCGImagePropertyTIFFModel] == nil)
        // It is a JPEG whatever it started as, and the size says what the data holds.
        let source = try #require(CGImageSourceCreateWithData(screenshot.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let size = try #require(DirtyPhoto.pixelSize(of: screenshot.data))
        #expect(size.width == screenshot.pixelWidth && size.height == screenshot.pixelHeight)
    }

    @Test func aDirtyScreenshotSizedLikeAnIPhone12() async throws {
        let dirty = DirtyPhoto.jpeg(width: 1170, height: 2532)
        let found = DirtyPhoto.metadataDictionaries(in: dirty)
        for kind in ["{Exif}", "{GPS}", "{TIFF}", "{IPTC}"] {
            #expect(found.contains { $0.hasPrefix(kind) }, "The test picture has no \(kind): \(found)")
        }
        let clean = try await ScreenshotPreparer().prepare(dirty)
        #expect(DirtyPhoto.metadataDictionaries(in: clean.data).isEmpty)
        #expect(clean.data.count <= FeedbackScreenshot.maximumBytes)
        // 2,000 pixels on the long side at most: text stays readable.
        #expect(max(clean.pixelWidth, clean.pixelHeight) <= 2_000)
        #expect(clean.pixelHeight > clean.pixelWidth)
    }

    @Test func aLargePictureIsShrunkUntilItFits() async throws {
        let big = DirtyPhoto.jpeg(width: 3_000, height: 4_000)
        let clean = try await ScreenshotPreparer().prepare(big)
        #expect(clean.data.count <= FeedbackScreenshot.maximumBytes)
        #expect(max(clean.pixelWidth, clean.pixelHeight) <= 2_000)
        #expect(DirtyPhoto.metadataDictionaries(in: clean.data).isEmpty)
    }

    @Test func aNoisyPictureIsShrunkFurtherToFitAndOneThatCannotFitIsTooLarge() async throws {
        // Random pixels barely compress, so it takes a smaller picture and a lower quality.
        let noise = DirtyPhoto.jpeg(width: 2_400, height: 3_200, metadata: false, noise: true)
        let fitted = try await ScreenshotPreparer().prepare(noise)
        #expect(fitted.data.count <= FeedbackScreenshot.maximumBytes)
        #expect(max(fitted.pixelWidth, fitted.pixelHeight) < 2_000)
        // With less room than any picture could fit in, it says so instead of sending too much.
        await #expect(throws: FeedbackScreenshotProblem.tooLarge) {
            try await ScreenshotPreparer(maximumBytes: 1_000).prepare(noise)
        }
    }

    @Test func aFileThatIsNotAPictureIsUnreadable() async {
        await #expect(throws: FeedbackScreenshotProblem.unreadable) {
            try await ScreenshotPreparer().prepare(Data("not a picture".utf8))
        }
        await #expect(throws: FeedbackScreenshotProblem.unreadable) { try await ScreenshotPreparer().prepare(Data()) }
    }
}
