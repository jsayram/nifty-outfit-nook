import Foundation
import Models

/// The `ImageProvider` for the sample wardrobe: it reads the bundled photos, cutouts, her
/// example try-on photo and the try-on previews (`SampleWardrobe`), and has no picture for any
/// other reference, so those pieces keep their drawings.
///
/// With `drawnSamples` it also draws the eight sample photos of `photos=samples`
/// (`SamplePhotoProvider`). Everything comes from the app's own bundle: nothing is downloaded. The
/// files are already small, and the image loader shrinks each one to the size shown.
public struct SampleWardrobeProvider: ImageProvider {
    private let drawnSamples: SamplePhotoProvider?

    public init(drawnSamples: Bool = false) {
        self.drawnSamples = drawnSamples ? SamplePhotoProvider() : nil
    }

    public func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
        guard let resource = SampleWardrobe.Resource(reference) else {
            return try await drawnSamples?.imageData(for: reference, maxPixelSize: maxPixelSize)
        }
        return await Self.read(resource)
    }

    @concurrent
    private static func read(_ resource: SampleWardrobe.Resource) async -> Data? {
        guard let url = resource.url else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
}
