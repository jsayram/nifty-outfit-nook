import CoreGraphics
import Foundation
import Models

// Sample data is compiled only in Debug: Release builds ship none (Phase 20a).
#if DEBUG
    /// An `ImageProvider` for `-fixtures …:photos=samples` (Phase 8b): it draws the sample photos and
    /// their stand-in cutouts from `SamplePhotoGarments`, and has no picture for anything else, so
    /// the other pieces keep their drawings.
    ///
    /// Everything is drawn on the phone; nothing is downloaded. Each picture is drawn at most the
    /// size asked for (a cutout is then cropped to its garments), and the image loader keeps what
    /// it shows.
    public struct SamplePhotoProvider: ImageProvider {
        public init() {}

        public func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
            guard let (scene, isCutout) = SamplePhotoGarments.scene(for: reference) else { return nil }
            return await Self.draw(scene, isCutout: isCutout, maxPixelSize: maxPixelSize)
        }

        @concurrent
        private static func draw(_ scene: SyntheticGarmentPhotos.Scene, isCutout: Bool, maxPixelSize: Int) async
            -> Data?
        {
            // The scenes are 4:5, portrait.
            let height = max(50, min(1500, maxPixelSize))
            let width = height * 4 / 5
            let data: Data
            if isCutout {
                // Cropped to the garments, as a real cutout is, with a pixel or two to spare.
                let bounds = SamplePhotoGarments.measure(scene).bounds
                let crop = CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
                    .insetBy(dx: -0.01, dy: -0.01)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                data = SyntheticGarmentPhotos.cutoutPNG(scene, width: width, height: height, crop: crop)
            } else {
                data = SyntheticGarmentPhotos.jpeg(scene, width: width, height: height)
            }
            return data.isEmpty ? nil : data
        }
    }
#endif
