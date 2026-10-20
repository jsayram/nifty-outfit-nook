import CoreGraphics
import Foundation
import ImageIO
import Models
import Testing
import UniformTypeIdentifiers

@testable import Services

/// The kept copy of a photo carries no location and no other metadata (Phase 22a,
/// SECURITY_STANDARD.md §4), whatever the picker or camera handed over.
struct PhotoCleanerTests {
    /// The formats the picker hands over with `preferredItemEncoding: .current`: HEIC from the
    /// camera, JPEG from older photos and other apps, PNG from screenshots. The HEIC is a fixed
    /// file, since the simulator can't write HEIC, and its cases run on a device only (`HEICSupport`).
    static let formats: [UTType] = HEICSupport.isReliable ? [.heic, .jpeg, .png] : [.jpeg, .png]

    @Test(arguments: formats)
    func theTestPhotoReallyCarriesALocation(_ type: UTType) throws {
        let photo = try #require(PhotoWithMetadata.make(type))
        let properties = try #require(PhotoWithMetadata.properties(of: photo))
        let gps = try #require(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        #expect(gps[kCGImagePropertyGPSLatitude] as? Double == PhotoWithMetadata.latitude)
        #expect(properties[kCGImagePropertyTIFFDictionary] != nil)
        // The byte search below finds what's there, so finding nothing later means something.
        #expect(PhotoWithMetadata.plantedTextFound(in: photo).contains("NookTestSerial42"))
        #expect(PhotoWithMetadata.metadataValues(of: photo).contains { $0.contains("NookTestCreator") })
    }

    @Test(arguments: formats)
    func theKeptCopyHasNoLocationOrCameraDetails(_ type: UTType) throws {
        let photo = try #require(PhotoWithMetadata.make(type))
        let clean = try PhotoCleaner.clean(photo)
        let properties = try #require(PhotoWithMetadata.properties(of: clean.data))

        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyIPTCDictionary] == nil)
        #expect(properties[kCGImagePropertyMakerAppleDictionary] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        #expect(tiff[kCGImagePropertyTIFFSoftware] == nil)
        #expect(tiff[kCGImagePropertyTIFFDateTime] == nil)
        // ImageIO writes its own colour space and size fields in a JPEG's Exif. Nothing else.
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let allowedExif: Set<String> = [
            kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension,
        ].map { $0 as String }.reduce(into: []) { $0.insert($1) }
        #expect(Set(exif.keys.map { $0 as String }).isSubset(of: allowedExif))
        // Nothing planted is left anywhere in the file, metadata or not.
        #expect(PhotoWithMetadata.plantedTextFound(in: clean.data).isEmpty)
        #expect(!PhotoWithMetadata.metadataValues(of: clean.data).contains { $0.contains("NookTestCreator") })
        #expect(!PhotoWithMetadata.metadataValues(of: clean.data).contains { $0.contains("40.6892") })
    }

    /// The orientation flag goes with the rest of the metadata, so the pixels are turned upright
    /// instead: a photo stored sideways (1,200 x 900, or the HEIC's 240 x 180) is kept tall.
    @Test(arguments: formats)
    func thePhotoIsKeptUpright(_ type: UTType) throws {
        let photo = try #require(PhotoWithMetadata.make(type, width: 1200, height: 900, orientation: .right))
        let stored = try #require(PhotoWithMetadata.storedSize(of: photo))
        #expect(stored.width > stored.height)
        let clean = try PhotoCleaner.clean(photo)
        #expect(clean.pixelWidth == stored.height)
        #expect(clean.pixelHeight == stored.width)
        let properties = try #require(PhotoWithMetadata.properties(of: clean.data))
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        #expect(orientation == 1)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == stored.height)
    }

    @Test(.enabled(if: HEICSupport.isReliable, HEICSupport.skipReason))
    func aHEICPhotoBecomesAJPEG() throws {
        let clean = try PhotoCleaner.clean(try #require(PhotoWithMetadata.make(.heic)))
        let source = try #require(CGImageSourceCreateWithData(clean.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func aBigPhotoIsCappedAtTheLongSide() throws {
        let photo = try #require(PhotoWithMetadata.make(.jpeg, width: 3000, height: 2000, orientation: .up))
        let clean = try PhotoCleaner.clean(photo, options: PhotoCleaner.Options(maxPixelSize: 1500))
        #expect(clean.pixelWidth == 1500)
        #expect(clean.pixelHeight == 1000)
    }

    @Test func anIPhonePhotoKeepsItsFullSize() throws {
        let photo = try #require(PhotoWithMetadata.make(.jpeg, width: 4032, height: 3024, orientation: .up))
        let clean = try PhotoCleaner.clean(photo)
        #expect(clean.pixelWidth == 4032)
        #expect(clean.pixelHeight == 3024)
    }

    @Test func somethingThatIsntAPictureIsRefused() {
        #expect(throws: PhotoIntakeError.unreadable) { try PhotoCleaner.clean(Data("not a photo".utf8)) }
        #expect(throws: PhotoIntakeError.unreadable) { try PhotoCleaner.clean(Data()) }
    }

    @Test func tooManyPixelsAreRefusedUnread() throws {
        let photo = try #require(PhotoWithMetadata.make(.jpeg, width: 1000, height: 1000, orientation: .up))
        #expect(throws: PhotoIntakeError.unreadable) {
            try PhotoCleaner.clean(photo, options: PhotoCleaner.Options(maxSourcePixels: 999_999))
        }
    }
}
