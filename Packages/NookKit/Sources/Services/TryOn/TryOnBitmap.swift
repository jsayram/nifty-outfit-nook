import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An opaque RGB picture in memory, 8 bits a channel, rows top to bottom: what the try-on steps
/// (Phase 33a) read and write pixel by pixel. Pixels are stored RGBA with alpha always 255.
public struct TryOnBitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0) {
        self.width = width
        self.height = height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = red
            pixels[index + 1] = green
            pixels[index + 2] = blue
        }
        self.pixels = pixels
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    @inline(__always) func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    public func rgb(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let index = offset(x, y)
        return (pixels[index], pixels[index + 1], pixels[index + 2])
    }

    public mutating func set(_ x: Int, _ y: Int, _ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        let index = offset(x, y)
        pixels[index] = red
        pixels[index + 1] = green
        pixels[index + 2] = blue
    }

    // MARK: Converting

    /// Draws `image` into a new bitmap of this size (scaled to fill it).
    public init?(_ image: CGImage, width: Int? = nil, height: Int? = nil) {
        let width = width ?? image.width
        let height = height ?? image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Decodes JPEG, PNG, HEIC or WebP bytes, upright, no larger than `maxPixelSize` on the long
    /// side.
    public static func decode(_ data: Data, maxPixelSize: Int) -> TryOnBitmap? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return TryOnBitmap(image)
    }

    public var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// JPEG with no metadata at all (no EXIF, GPS or thumbnail): only the pixels.
    public func jpeg(quality: Double) -> Data? {
        guard let image = cgImage else { return nil }
        return Self.encode(image, type: .jpeg, quality: quality)
    }

    public func png() -> Data? {
        guard let image = cgImage else { return nil }
        return Self.encode(image, type: .png, quality: nil)
    }

    static func encode(_ image: CGImage, type: UTType, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The same picture at another size.
    public func resized(width: Int, height: Int) -> TryOnBitmap? {
        if width == self.width && height == self.height { return self }
        guard let image = cgImage else { return nil }
        return TryOnBitmap(image, width: width, height: height)
    }

    /// The middle of the picture cut to `aspect` (width over height), then scaled to the size.
    public func fitted(width: Int, height: Int) -> TryOnBitmap? {
        let target = Double(width) / Double(height)
        let current = Double(self.width) / Double(self.height)
        guard let image = cgImage else { return nil }
        var crop = CGRect(x: 0, y: 0, width: self.width, height: self.height)
        if abs(current - target) > 0.005 {
            if current > target {
                let cropWidth = Double(self.height) * target
                crop = CGRect(x: (Double(self.width) - cropWidth) / 2, y: 0, width: cropWidth, height: Double(self.height))
            } else {
                let cropHeight = Double(self.width) / target
                crop = CGRect(x: 0, y: (Double(self.height) - cropHeight) / 2, width: Double(self.width), height: cropHeight)
            }
        }
        guard let cropped = image.cropping(to: crop.integral) else { return nil }
        return TryOnBitmap(cropped, width: width, height: height)
    }
}

/// A grey level per pixel, 0 (out) to 255 (in), rows top to bottom: a person's outline, a head
/// shape, or where grey is left.
public struct TryOnMask: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [UInt8]

    public init(width: Int, height: Int, values: [UInt8]) {
        precondition(values.count == width * height)
        self.width = width
        self.height = height
        self.values = values
    }

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.init(width: width, height: height, values: [UInt8](repeating: fill, count: width * height))
    }

    @inline(__always) public subscript(x: Int, y: Int) -> UInt8 {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }

    /// How many pixels are at least `threshold`.
    public func count(atLeast threshold: UInt8) -> Int { values.count { $0 >= threshold } }

    /// The smallest box holding every pixel at least `threshold`, or `nil` when there's none.
    public func bounds(atLeast threshold: UInt8) -> CGRect? {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where values[y * width + x] >= threshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Every pixel within `radius` of one at least 128 becomes 255; the rest 0. A square
    /// neighbourhood, done as two passes.
    public func dilated(by radius: Int) -> TryOnMask {
        guard radius > 0 else { return thresholded() }
        var horizontal = [UInt8](repeating: 0, count: values.count)
        for y in 0..<height {
            var last = -radius - 1
            // Left to right, then right to left, marking pixels within `radius` of an "in" pixel.
            for x in 0..<width {
                if values[y * width + x] >= 128 { last = x }
                if x - last <= radius { horizontal[y * width + x] = 255 }
            }
            last = width + radius + 1
            for x in stride(from: width - 1, through: 0, by: -1) {
                if values[y * width + x] >= 128 { last = x }
                if last - x <= radius { horizontal[y * width + x] = 255 }
            }
        }
        var result = [UInt8](repeating: 0, count: values.count)
        for x in 0..<width {
            var last = -radius - 1
            for y in 0..<height {
                if horizontal[y * width + x] == 255 { last = y }
                if y - last <= radius { result[y * width + x] = 255 }
            }
            last = height + radius + 1
            for y in stride(from: height - 1, through: 0, by: -1) {
                if horizontal[y * width + x] == 255 { last = y }
                if last - y <= radius { result[y * width + x] = 255 }
            }
        }
        return TryOnMask(width: width, height: height, values: result)
    }

    /// 255 where at least 128, else 0.
    public func thresholded() -> TryOnMask {
        TryOnMask(width: width, height: height, values: values.map { $0 >= 128 ? 255 : 0 })
    }

    /// A box blur of `radius`, for soft edges. Two passes with running sums.
    public func blurred(by radius: Int) -> TryOnMask {
        guard radius > 0 else { return self }
        func pass(_ input: [UInt8], horizontal: Bool) -> [UInt8] {
            var output = [UInt8](repeating: 0, count: input.count)
            let lines = horizontal ? height : width
            let length = horizontal ? width : height
            for line in 0..<lines {
                @inline(__always) func at(_ i: Int) -> Int {
                    let clamped = min(max(i, 0), length - 1)
                    return horizontal ? line * width + clamped : clamped * width + line
                }
                var sum = 0
                for i in -radius...radius { sum += Int(input[at(i)]) }
                let span = 2 * radius + 1
                for i in 0..<length {
                    output[at(i)] = UInt8(sum / span)
                    sum += Int(input[at(i + radius + 1)]) - Int(input[at(i - radius)])
                }
            }
            return output
        }
        return TryOnMask(width: width, height: height, values: pass(pass(values, horizontal: true), horizontal: false))
    }

    /// Pixels in both.
    public func intersected(with other: TryOnMask) -> TryOnMask {
        TryOnMask(width: width, height: height, values: zip(values, other.values).map { min($0, $1) })
    }

    /// The mask at another size.
    public func resized(width: Int, height: Int) -> TryOnMask {
        if width == self.width && height == self.height { return self }
        var result = [UInt8](repeating: 0, count: width * height)
        let scaleX = Double(self.width) / Double(width)
        let scaleY = Double(self.height) / Double(height)
        for y in 0..<height {
            let sourceY = min(self.height - 1, Int((Double(y) + 0.5) * scaleY))
            for x in 0..<width {
                let sourceX = min(self.width - 1, Int((Double(x) + 0.5) * scaleX))
                result[y * width + x] = values[sourceY * self.width + sourceX]
            }
        }
        return TryOnMask(width: width, height: height, values: result)
    }

    /// A grey PNG of the mask, for keeping it between steps.
    public func png() -> Data? {
        guard let provider = CGDataProvider(data: Data(values) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return TryOnBitmap.encode(image, type: .png, quality: nil)
    }

    /// Reads a mask written by `png()`.
    public static func decode(_ data: Data) -> TryOnMask? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let width = image.width
        let height = image.height
        var values = [UInt8](repeating: 0, count: width * height)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? TryOnMask(width: width, height: height, values: values) : nil
    }
}
