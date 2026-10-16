import ImageIO
import Models
import SwiftUI
import UIKit

/// Loads garment pictures through the `ImageProvider`, shrinks them to the size they're shown at,
/// and keeps them in memory, so a long grid never decodes a full photo per cell.
///
/// Stage A's provider has no pictures and answers `nil`, so every piece draws its placeholder
/// (`GarmentPlaceholderArt`). The path for real photos is already here for Phases 7b, 8b and 22b:
/// the provider returns the bytes, the loader downsamples them away from the main actor with
/// ImageIO (`CGImageSourceCreateThumbnailAtIndex`, which never decodes the full image), and
/// caches the result by picture and pixel size. A picture the provider says isn't there (it answers
/// `nil`), or whose bytes can't be read, is remembered too, so scrolling back over it doesn't ask
/// again; at most `missingLimit` are remembered, and the list starts over when it's full. A load
/// that fails (the provider throws) isn't remembered, so the next time the cell shows it asks
/// again. Two cells asking for the same picture at once share one load.
///
/// Garment photos are Personal data (DATA_MAP.md). The cache is in memory only: nothing is
/// written to disk, and it empties under memory pressure.
final class GarmentImageLoader {
    private let provider: any ImageProvider
    private let cache = NSCache<NSString, UIImage>()
    private var missing: Set<Key> = []
    private let missingLimit: Int
    private var loading: [Key: Task<Outcome, Never>] = [:]

    /// How many times the provider was asked, for tests.
    private(set) var providerRequests = 0

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

    init(provider: any ImageProvider, countLimit: Int = 300, missingLimit: Int = 1_000) {
        self.provider = provider
        self.missingLimit = missingLimit
        cache.countLimit = countLimit
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
            guard let data, let image = await Self.downsample(data, maxPixelSize: maxPixelSize) else {
                return .notThere
            }
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

    private static func image(in outcome: Outcome) -> UIImage? {
        if case .image(let image) = outcome { image } else { nil }
    }

    /// The picture if it has already loaded, without asking the provider. Lets a view show a
    /// loaded picture on its first frame, and still images draw one at all.
    func cachedImage(for reference: PhotoReference, maxPixelSize: Int) -> UIImage? {
        cache.object(forKey: Key(reference: reference, maxPixelSize: maxPixelSize).cacheName)
    }

    /// True when the provider had no picture for `reference` at this size.
    func isMissing(_ reference: PhotoReference, maxPixelSize: Int) -> Bool {
        if case .noPhoto = reference { return true }
        return missing.contains(Key(reference: reference, maxPixelSize: maxPixelSize))
    }

    /// Decodes `data` straight to a thumbnail no larger than `maxPixelSize`, off the main actor.
    @concurrent
    nonisolated static func downsample(_ data: Data, maxPixelSize: Int) async -> UIImage? {
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

extension GarmentImageLoader.Key {
    fileprivate var cacheName: NSString {
        "\(reference)|\(maxPixelSize)" as NSString
    }
}

extension EnvironmentValues {
    /// Garment pictures for every screen, built once at the root from the services' image provider.
    @Entry var garmentImages: GarmentImageLoader?
}
