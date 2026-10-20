import CoreGraphics
import Fixtures
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Test photos that carry what a phone photo can: a GPS position, the camera and lens, the time,
/// a serial number, a caption and an XMP creator, stored sideways with an orientation flag. Each
/// planted value is a string the tests can look for in the cleaned file's bytes too.
enum PhotoWithMetadata {
    static let latitude = 40.6892
    static let longitude = 74.0445
    /// Text planted in the metadata. None of it may survive cleaning.
    static let plantedText = [
        "NookTestMaker", "NookTestModel", "NookTestLens", "NookTestSerial42", "2026:10:20 09:41:00",
        "NookTestCity", "NookTestCreator", "NookTestSoftware",
    ]

    /// A photo of `width` x `height` stored pixels, as `type`, with every kind of metadata above
    /// and `orientation` (6 means "turn right to show": stored sideways, as an iPhone does).
    ///
    /// HEIC is the fixed `heic` file instead, whatever the size asked for: the simulator can't
    /// write HEIC (`PhotoCleaner`), only read it.
    static func make(
        _ type: UTType = .jpeg, width: Int = 1200, height: Int = 900, orientation: CGImagePropertyOrientation = .right
    ) -> Data? {
        if type == .heic { return heic }
        guard let image = SyntheticGarmentPhotos.draw(.flatLayTee, width: width, height: height) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyOrientation: orientation.rawValue,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: latitude, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: longitude, kCGImagePropertyGPSLongitudeRef: "W",
                kCGImagePropertyGPSAltitude: 12.5,
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "NookTestMaker", kCGImagePropertyTIFFModel: "NookTestModel",
                kCGImagePropertyTIFFSoftware: "NookTestSoftware",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:20 09:41:00",
                kCGImagePropertyExifLensModel: "NookTestLens",
                kCGImagePropertyExifBodySerialNumber: "NookTestSerial42",
            ],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "NookTestCity"],
        ]
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataSetValueWithPath(metadata, nil, "dc:creator" as CFString, "NookTestCreator" as CFString)
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A 240 x 180 HEIC stored sideways (orientation 6) with the same metadata as `make`, written
    /// with ImageIO on a Mac (a navy square on cream, nothing real). 1,538 bytes.
    static let heic = Data(
        base64Encoded: [
            "AAAAJGZ0eXBoZWljAAAAAG1pZjFNaVBybWlhZk1pSEJoZWljAAACB21ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAA",
            "AAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAADnBpdG0AAAAAAAEAAABhaWluZgAAAAAAAwAAABVp",
            "bmZlAgAAAAABAABodmMxAAAAABVpbmZlAgAAAQACAABFeGlmAAAAAClpbmZlAgAAAQADAABtaW1lAGFwcGxpY2F0aW9uL3JkZit4",
            "bWwAAAAAKGlyZWYAAAAAAAAADmNkc2MAAgABAAEAAAAOY2RzYwADAAEAAQAAAOVpcHJwAAAAxGlwY28AAAATY29scm5jbHgAAgAC",
            "AAaAAAAADGNsbGkAywBAAAAAFGlzcGUAAAAAAAAA8AAAALQAAAAJaXJvdAMAAAAQcGl4aQAAAAADCAgIAAAAcGh2Y0MBA3AAAACw",
            "AAAAAAA88AD8/fj4AAALA6AAAQAXQAEMAf//A3AAAAMAsAAAAwAAAwA8cCShAAEAIkIBAQNwAAADALAAAAMAAAMAPKAeIDB8+Ie5",
            "FlU3AgIGAICiAAEACUQBwGPLIRFNkAAAABlpcG1hAAAAAAAAAAEAAQaBAgMFhoQAAAA6aWxvYwAAAABEAAADAAEAAAABAAAE5wAA",
            "ARsAAgAAAAEAAAI7AAABZgADAAAAAQAAA6EAAAFGAAAAAW1kYXQAAAAAAAAD1wAAAAZFeGlmAABNTQAqAAAACAAGAQ8AAgAAAA4A",
            "AABWARAAAgAAAA4AAABkARIAAwAAAAEABgAAATEAAgAAABEAAAByh2kABAAAAAEAAACEiCUABAAAAAEAAADiAAAAAE5vb2tUZXN0",
            "TWFrZXIATm9va1Rlc3RNb2RlbABOb29rVGVzdFNvZnR3YXJlAAAAA5ADAAIAAAAUAAAArqQxAAIAAAARAAAAwqQ0AAIAAAANAAAA",
            "1AAAAAAyMDI2OjEwOjIwIDA5OjQxOjAwAE5vb2tUZXN0U2VyaWFsNDIAAE5vb2tUZXN0TGVucwAAAAUAAQACAAAAAk4AAAAAAgAF",
            "AAAAAwAAASQAAwACAAAAAlcAAAAABAAFAAAAAwAAATwABgAFAAAAAQAAAVQAAAAAAAAAKAAAAAEAAAApAAAAAQAACEAAAABkAAAA",
            "SgAAAAEAAAACAAAAAQAAD7QAAABkAAAAGQAAAAI8eDp4bXBtZXRhIHhtbG5zOng9ImFkb2JlOm5zOm1ldGEvIiB4OnhtcHRrPSJY",
            "TVAgQ29yZSA2LjAuMCI+CiAgIDxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3lu",
            "dGF4LW5zIyI+CiAgICAgIDxyZGY6RGVzY3JpcHRpb24gcmRmOmFib3V0PSIiCiAgICAgICAgICAgIHhtbG5zOmRjPSJodHRwOi8v",
            "cHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+CiAgICAgICAgIDxkYzpjcmVhdG9yPk5vb2tUZXN0Q3JlYXRvcjwvZGM6Y3JlYXRv",
            "cj4KICAgICAgPC9yZGY6RGVzY3JpcHRpb24+CiAgIDwvcmRmOlJERj4KPC94OnhtcG1ldGE+CgAAARcoAa+Y9NkMDxr30fRvQ5c/",
            "KRw60zWJeCy5IEqKSfOVg5kwuAzEvEVOROZpC9wTWCgHQMCtF3VLrlbfNNBnXpTHBnLih75QZDP9Omel48YqnIyzLX+ppR2C3v3A",
            "Q8Ab0cD8xbAJ2FdKtIhpbKekV52D/7Fefm/4Oi7XKsFL6+3fW25B7e+2e6tgENNSewbgt4ACtMI/JP3o4AB7AAZsAZBwAHwAFHAC",
            "x0C9dku1UpARUhk66QxzHUimc96QSFixPi5qI2xGaZdL9SRfmar3nr3COYD4YqU6uEEjeeeHNjHodctW/f3Q0ZYgpvAgIDcGeamQ",
            "r/9zK69L49ytH+eR3ZLN8zvUP1vuRDoqLSm82QfY5OLrZAFMA2I=",
        ].joined())

    /// The stored size, before the orientation flag is applied.
    static func storedSize(of data: Data) -> (width: Int, height: Int)? {
        guard let properties = properties(of: data),
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    static func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// Every XMP tag's value, as text (an array's items inside its description).
    static func metadataValues(of data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else { return [] }
        return tags.compactMap { CGImageMetadataTagCopyValue($0).map { "\($0)" } }
    }

    /// The planted strings found anywhere in the file's bytes.
    static func plantedTextFound(in data: Data) -> [String] {
        plantedText.filter { data.range(of: Data($0.utf8)) != nil }
    }
}
