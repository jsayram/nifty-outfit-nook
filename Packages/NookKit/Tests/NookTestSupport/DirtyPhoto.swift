import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture that carries the kinds of metadata a phone puts in a photo or a screenshot, and a
/// way to look for that metadata in bytes, so a test can show it is gone (Phase 24d, SECURITY_STANDARD §4).
public enum DirtyPhoto {
    public static let place = "47.6062 N, 122.3321 W"
    public static let device = "iPhone 12"
    public static let caption = "A private caption"

    /// A gradient as a JPEG. With `metadata`, it has Exif (a comment and a time), GPS, TIFF (make
    /// and model) and IPTC (a caption) dictionaries.
    public static func jpeg(width: Int = 390, height: Int = 844, metadata: Bool = true, noise: Bool = false) -> Data {
        let data = NSMutableData()
        guard let image = draw(width: width, height: height, noise: noise),
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return Data() }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if metadata {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifUserComment: "Taken at home",
                kCGImagePropertyExifDateTimeOriginal: "2026:10:21 09:30:00",
            ]
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 47.6062, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.3321, kCGImagePropertyGPSLongitudeRef: "W",
            ]
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: device,
            ]
            properties[kCGImagePropertyIPTCDictionary] = [kCGImagePropertyIPTCCaptionAbstract: caption]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }

    /// The same, as a PNG. With `metadata`, it has a text chunk-style description and a GPS
    /// dictionary where ImageIO keeps them.
    public static func png(width: Int = 390, height: Int = 844, metadata: Bool = true) -> Data {
        let data = NSMutableData()
        guard let image = draw(width: width, height: height, noise: false),
            let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        var properties: [CFString: Any] = [:]
        if metadata {
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: "Taken at \(place)"]
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 47.6062, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.3321, kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }

    /// What the picture says about where, when, with what or about whom: a dictionary such as
    /// "{GPS}" or "{IPTC}", or a field such as "{TIFF}.Make". The technical entries every JPEG or
    /// PNG carries (size, colour, resolution, orientation) don't count. Empty for a clean picture.
    public static func metadataDictionaries(in data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return ["unreadable"] }
        let allowed: [String: Set<String>] = [
            "{Exif}": [
                "ExifVersion", "PixelXDimension", "PixelYDimension", "ColorSpace", "ComponentsConfiguration",
                "FlashPixVersion",
            ],
            "{TIFF}": ["Orientation", "XResolution", "YResolution", "ResolutionUnit"],
            "{PNG}": ["Gamma", "InterlaceType", "XPixelsPerMeter", "YPixelsPerMeter", "sRGBIntent"],
            "{JFIF}": ["JFIFVersion", "XDensity", "YDensity", "DensityUnit", "IsProgressive"],
        ]
        var found: [String] = []
        for (key, value) in properties {
            let name = key as String
            guard name.hasPrefix("{") else { continue }
            guard let permitted = allowed[name] else {
                found.append(name)
                continue
            }
            for field in (value as? [CFString: Any])?.keys ?? [:].keys where !permitted.contains(field as String) {
                found.append("\(name).\(field)")
            }
        }
        return found.sorted()
    }

    /// The picture's size in pixels.
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    private static func draw(width: Int, height: Int, noise: Bool) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        if noise, let buffer = context.data {
            // Random pixels do not compress: a picture that can only fit by being shrunk.
            var generator = SystemRandomNumberGenerator()
            let bytes = buffer.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
            for index in 0..<(context.bytesPerRow * height) {
                bytes[index] = UInt8.random(in: 0...255, using: &generator)
            }
        } else {
            for row in stride(from: 0, to: height, by: 8) {
                let shade = CGFloat(row) / CGFloat(height)
                context.setFillColor(CGColor(red: 0.9 - 0.4 * shade, green: 0.7, blue: 0.4 + 0.4 * shade, alpha: 1))
                context.fill(CGRect(x: 0, y: row, width: width, height: 8))
            }
        }
        return context.makeImage()
    }
}
