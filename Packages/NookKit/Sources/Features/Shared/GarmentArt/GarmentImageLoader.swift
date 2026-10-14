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
/// caches the result by picture and pixel size. A picture that comes back empty is remembered too,
/// so scrolling back over it doesn't ask again. Two cells asking for the same picture at once
/// share one load.
///
/// Garment photos are Personal data (DATA_MAP.md). The cache is in memory only: nothing is
/// written to disk, and it empties under memory pressure.
final class GarmentImageLoader {
    private let provider: any ImageProvider
    private let cache = NSCache<NSString, UIImage>()
    private var missing: Set<Key> = []
    private var loading: [Key: Task<UIImage?, Never>] = [:]

    /// How many times the provider was asked, for tests.
    private(set) var providerRequests = 0

    struct Key: Hashable {
        let reference: PhotoReference
        let maxPixelSize: Int
    }

    init(provider: any ImageProvider, countLimit: Int = 300) {
        self.provider = provider
        cache.countLimit = countLimit
    }

    /// The picture for `reference`, at most `maxPixelSize` pixels on its long side, or `nil` when
    /// there's no picture (or it couldn't be read), so the caller draws the placeholder.
    func image(for reference: PhotoReference, maxPixelSize: Int) async -> UIImage? {
        if case .noPhoto = reference { return nil }
        let key = Key(reference: reference, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key.cacheName) { return cached }
        if missing.contains(key) { return nil }
        if let running = loading[key] { return await running.value }

        providerRequests += 1
        let provider = provider
        let task = Task { () -> UIImage? in
            let data: Data?
            do {
                data = try await provider.imageData(for: reference, maxPixelSize: maxPixelSize)
            } catch {
                data = nil
            }
            guard let data else { return nil }
            return await Self.downsample(data, maxPixelSize: maxPixelSize)
        }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image {
            cache.setObject(image, forKey: key.cacheName)
        } else {
            missing.insert(key)
        }
        return image
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

/// A garment's picture: the photo once it has loaded, the placeholder drawing until then and for
/// pieces with no photo. Sized by its frame; the photo is requested at that size in pixels.
struct GarmentPicture: View {
    let photo: PhotoReference
    let category: GarmentCategory
    let colors: [ColorName]
    /// The longest side the picture is shown at, in points.
    let pointSize: CGFloat

    @Environment(\.garmentImages) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                GarmentPlaceholderArt(category: category, colors: colors)
            }
        }
        .task(id: photo) {
            guard let loader, photo != .noPhoto else { return }
            image = await loader.image(for: photo, maxPixelSize: Int((pointSize * displayScale).rounded(.up)))
        }
    }
}
