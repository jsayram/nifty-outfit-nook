import Foundation
import Models

/// Makes the screenshot she attaches to a note (Phase 24d): the same clean copy the app makes of
/// any photo (`PhotoCleaner`: upright, from the pixels alone, so no EXIF, location, time, device
/// or caption survives), made smaller until it fits what the backend accepts. A screenshot of
/// text stays readable at 1,600 pixels; it only gets smaller if it must.
///
/// The backend removes metadata again from whatever it receives (its image cleaner), because it
/// can't know what the app did. Doing it here too means it never leaves the phone.
public struct ScreenshotPreparer: FeedbackScreenshotPreparing {
    /// Long side in pixels and JPEG quality, tried in order until the picture fits.
    static let steps: [(pixels: Int, quality: Double)] = [(2_000, 0.8), (1_600, 0.7), (1_280, 0.6), (1_024, 0.5)]

    private let maximumBytes: Int

    /// - Parameter maximumBytes: how large the result may be. The backend's limit, unless a test
    ///   asks for less.
    public init(maximumBytes: Int = FeedbackScreenshot.maximumBytes) {
        self.maximumBytes = maximumBytes
    }

    public func prepare(_ data: Data) async throws(FeedbackScreenshotProblem) -> FeedbackScreenshot {
        for step in Self.steps {
            let options = PhotoCleaner.Options(maxPixelSize: step.pixels, quality: step.quality)
            guard let clean = try? PhotoCleaner.clean(data, options: options) else { throw .unreadable }
            if clean.data.count <= maximumBytes {
                return FeedbackScreenshot(
                    data: clean.data, pixelWidth: clean.pixelWidth, pixelHeight: clean.pixelHeight)
            }
        }
        throw .tooLarge
    }
}
