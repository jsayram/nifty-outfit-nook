import CoreGraphics
import Foundation
import ImageIO
import Models
import UniformTypeIdentifiers

/// Makes the copy of a photo that the app keeps (Phase 22a, SECURITY_STANDARD.md §4).
///
/// The system picker includes a photo's location by default, and a phone photo also carries the
/// time, the camera and lens, and sometimes a serial number or a caption. None of that is kept.
/// The cleaner decodes the pixels, turns them upright (so the orientation tag isn't needed), and
/// writes a new JPEG from the pixels alone. Only what ImageIO writes for any JPEG is left: the
/// pixel size, the colour profile and colour space, and for some pictures the Exif version and
/// resolution. Depth, the HDR gain map, mattes and Live Photo parts are left out too, since only
/// the main picture is read.
///
/// JPEG, not HEIC: on the iOS 26.5 simulator a HEIC encode never finished (it waited forever in
/// VideoToolbox's `VTTileCompressionSessionEncodeTile` under `CGImageDestinationFinalize`), and
/// JPEG has no such dependency. HEIC would be about half the size; Phase 22b can weigh that on a
/// device with its storage numbers.
///
/// A photo with more than `maxSourcePixels` pixels is refused before anything is decoded, and a
/// larger one than `maxPixelSize` on its long side is scaled down while it's decoded, so a 48 MP
/// photo never sits in memory at full size. Thumbnails and the cache are Phase 22b.
public enum PhotoCleaner {
    public struct Options: Hashable, Sendable {
        /// The long side of the kept copy, in pixels. 4,096 keeps a 12 MP iPhone photo (4,032
        /// pixels) at full size and caps larger ones.
        public var maxPixelSize: Int
        /// Anything with more pixels is refused unread, as the cutout does (`ImageDownsampler`).
        public var maxSourcePixels: Int
        /// JPEG quality, 0 to 1.
        public var quality: Double

        public init(maxPixelSize: Int = 4_096, maxSourcePixels: Int = 100_000_000, quality: Double = 0.85) {
            self.maxPixelSize = maxPixelSize
            self.maxSourcePixels = maxSourcePixels
            self.quality = quality
        }

        public static let standard = Options()
    }

    /// The kept copy, a JPEG.
    public struct CleanPhoto: Sendable {
        public let data: Data
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    /// The photo, upright, without its metadata. Throws `unreadable` for anything that isn't a
    /// picture ImageIO can read, or is over the pixel limit.
    public static func clean(_ data: Data, options: Options = .standard) throws(PhotoIntakeError) -> CleanPhoto {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw .unreadable }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= options.maxSourcePixels else { throw .unreadable }

        // A thumbnail as large as the photo (or the cap) is the whole picture, decoded upright.
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), options.maxPixelSize),
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
            let encoded = encode(image, quality: options.quality)
        else { throw .unreadable }
        return CleanPhoto(data: encoded, pixelWidth: image.width, pixelHeight: image.height)
    }

    /// The pixels alone, as a JPEG. The only property passed is the quality, so nothing from the
    /// original file can reach the new one.
    static func encode(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
        return data as Data
    }
}
