import CoreGraphics
import Foundation
import ImageIO
import Models

/// Reads a photo at a working size without decoding it at full size first.
enum ImageDownsampler {
    /// The photo, upright, no larger than `maxPixelSize` on its long side. Pictures with more
    /// than `maxSourcePixels` pixels are refused before anything is decoded, so a hostile or
    /// broken file can't make the app decode a huge bitmap.
    static func image(from data: Data, maxPixelSize: Int, maxSourcePixels: Int) throws(CutoutError) -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw .unreadableImage }

        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= maxSourcePixels else { throw .imageTooLarge }

        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw .unreadableImage }
        return image
    }
}
