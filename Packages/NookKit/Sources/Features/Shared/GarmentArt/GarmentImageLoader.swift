import ImageIO
import Models
import SwiftUI
import UIKit

/// Loads garment pictures through the `ImageProvider`, shrinks them to the size they're shown at,
/// and keeps them in memory, so a long grid never decodes a full photo per cell.
///
/// The provider returns the bytes, the loader downsamples them away from the main actor with
/// ImageIO (`CGImageSourceCreateThumbnailAtIndex`, which never decodes the full image), and
/// caches the result by picture and pixel size. A picture the provider says isn't there (it answers
/// `nil`), or whose bytes can't be read, is remembered too, so scrolling back over it doesn't ask
/// again; at most `missingLimit` are remembered, and the list starts over when it's full. A load
/// that fails (the provider throws) isn't remembered, so the next time the cell shows it asks
/// again. Two cells asking for the same picture at once share one load.
///
/// A JPEG 2000 picture (the sample wardrobe's cutouts) is slow to decode, about 4 times a JPEG of
/// the same size. Any size above half of it costs a whole decode, so the first such request
/// decodes it once at full size and keeps it (`originals`), and from then on every size shown is
/// scaled down from that with Core Graphics instead of decoding the file again. A small size
/// asked for before then decodes cheaply from the file's lower resolution levels. Other formats
/// decode quickly to a thumbnail and don't keep a full-size copy.
///
/// Garment photos are Personal data (DATA_MAP.md). The cache is in memory only: nothing is
/// written to disk, and it empties under memory pressure.
final class GarmentImageLoader {
    private let provider: any ImageProvider
    private let cache = NSCache<NSString, UIImage>()
    /// Full-size decodes of slow formats, by reference, so each is decoded once (see above).
    private let originals = NSCache<NSString, Original>()
    private var decodingOriginals: [PhotoReference: Task<CGImage?, Never>] = [:]
    private var missing: Set<Key> = []
    private let missingLimit: Int
    private var loading: [Key: Task<Outcome, Never>] = [:]

    /// How many times the provider was asked, for tests.
    private(set) var providerRequests = 0
    /// How many full-size decodes of slow formats were made, for tests.
    private(set) var originalDecodes = 0

    /// Test hook for still snapshots: the picture's bytes, read at once. When set, `cachedImage`
    /// decodes a picture it doesn't hold yet from these bytes, so a still render shows the real
    /// photo on its first pass at whatever size the view asks for. Never set in the app.
    var synchronousData: ((PhotoReference) -> Data?)?

    struct Key: Hashable {
        let reference: PhotoReference
        let maxPixelSize: Int
    }

    /// What one load found.
    enum Outcome {
        case image(UIImage)
        /// No picture, or bytes that can't be decoded. Asking again gives the same answer.
        case notThere
        /// The provider failed. Asking again may work.
        case failed
    }

    /// - Parameter originalsByteLimit: the memory the full-size decodes may hold. 48 MB keeps
    ///   about 30 of the sample cutouts, a Saved Looks page's worth.
    init(
        provider: any ImageProvider, countLimit: Int = 300, missingLimit: Int = 1_000,
        originalsByteLimit: Int = 48 << 20
    ) {
        self.provider = provider
        self.missingLimit = missingLimit
        cache.countLimit = countLimit
        originals.totalCostLimit = originalsByteLimit
    }

    /// The picture for `reference`, at most `maxPixelSize` pixels on its long side, or `nil` when
    /// there's no picture (or it couldn't be read), so the caller draws the placeholder.
    func image(for reference: PhotoReference, maxPixelSize: Int) async -> UIImage? {
        if case .noPhoto = reference { return nil }
        let key = Key(reference: reference, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key.cacheName) { return cached }
        if missing.contains(key) { return nil }
        if let running = loading[key] { return Self.image(in: await running.value) }

        providerRequests += 1
        let provider = provider
        let task = Task { () -> Outcome in
            let data: Data?
            do {
                data = try await provider.imageData(for: reference, maxPixelSize: maxPixelSize)
            } catch {
                return .failed
            }
            guard let data else { return .notThere }
            if let longSide = Self.slowFormatLongSide(data) {
                // A size above half the picture costs a whole decode anyway (JPEG 2000 decodes
                // smaller sizes from its half, quarter and eighth resolution levels, cheaply).
                if let original = await self.original(
                    for: reference, data: data, decodeIfNeeded: maxPixelSize * 2 > longSide)
                {
                    return await Self.scaled(original, maxPixelSize: maxPixelSize).map(Outcome.image) ?? .notThere
                }
            }
            guard let image = await Self.downsample(data, maxPixelSize: maxPixelSize) else { return .notThere }
            return .image(image)
        }
        loading[key] = task
        let outcome = await task.value
        loading[key] = nil
        switch outcome {
        case .image(let image):
            cache.setObject(image, forKey: key.cacheName)
        case .notThere:
            if missing.count >= missingLimit { missing.removeAll() }
            missing.insert(key)
        case .failed:
            break
        }
        return Self.image(in: outcome)
    }

    /// The full-size decode of a slow format: kept, already being made, or, with
    /// `decodeIfNeeded`, made now away from the main actor. Views asking for different sizes at
    /// once share one decode.
    private func original(for reference: PhotoReference, data: Data, decodeIfNeeded: Bool) async -> CGImage? {
        let name = "\(reference)" as NSString
        if let kept = originals.object(forKey: name) { return kept.image }
        if let running = decodingOriginals[reference] { return await running.value }
        guard decodeIfNeeded else { return nil }
        originalDecodes += 1
        let task = Task { await Self.decodeWhole(data) }
        decodingOriginals[reference] = task
        let image = await task.value
        decodingOriginals[reference] = nil
        if let image {
            originals.setObject(Original(image), forKey: name, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    /// The long side in pixels of a JPEG 2000 picture, which ImageIO decodes in software, slowly;
    /// `nil` for any other format. Reads only the header.
    nonisolated static func slowFormatLongSide(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source), (type as String) == "public.jpeg-2000",
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(width, height)
    }

    /// Decodes the whole picture now (drawing it once into a bitmap, since ImageIO otherwise
    /// waits until the first draw), with its alpha.
    @concurrent
    nonisolated static func decodeWhole(_ data: Data) async -> CGImage? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return redraw(image, width: image.width, height: image.height)
    }

    /// `image` no larger than `maxPixelSize` on its long side, scaled down with Core Graphics.
    @concurrent
    nonisolated static func scaled(_ image: CGImage, maxPixelSize: Int) async -> UIImage? {
        let longSide = max(image.width, image.height)
        guard longSide > maxPixelSize, maxPixelSize > 0 else { return UIImage(cgImage: image) }
        let factor = Double(maxPixelSize) / Double(longSide)
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
        return redraw(image, width: width, height: height).map { UIImage(cgImage: $0) }
    }

    nonisolated private static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func image(in outcome: Outcome) -> UIImage? {
        if case .image(let image) = outcome { image } else { nil }
    }

    /// The picture if it has already loaded, without asking the provider. Lets a view show a
    /// loaded picture on its first frame, and still images draw one at all.
    func cachedImage(for reference: PhotoReference, maxPixelSize: Int) -> UIImage? {
        let name = Key(reference: reference, maxPixelSize: maxPixelSize).cacheName
        if let cached = cache.object(forKey: name) { return cached }
        guard let data = synchronousData?(reference),
            let image = Self.thumbnail(data, maxPixelSize: maxPixelSize)
        else { return nil }
        cache.setObject(image, forKey: name)
        return image
    }

    /// True when the provider had no picture for `reference` at this size.
    func isMissing(_ reference: PhotoReference, maxPixelSize: Int) -> Bool {
        if case .noPhoto = reference { return true }
        return missing.contains(Key(reference: reference, maxPixelSize: maxPixelSize))
    }

    /// Decodes `data` straight to a thumbnail no larger than `maxPixelSize`, off the main actor.
    @concurrent
    nonisolated static func downsample(_ data: Data, maxPixelSize: Int) async -> UIImage? {
        thumbnail(data, maxPixelSize: maxPixelSize)
    }

    nonisolated static func thumbnail(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// A decoded picture in an `NSCache`, which holds objects.
private final class Original: Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

extension GarmentImageLoader.Key {
    fileprivate var cacheName: NSString {
        "\(reference)|\(maxPixelSize)" as NSString
    }
}

extension EnvironmentValues {
    /// Garment pictures for every screen, built once at the root from the services' image provider.
    @Entry var garmentImages: GarmentImageLoader?
}
