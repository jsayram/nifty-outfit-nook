import Foundation
import Models

/// The photo step's stand-in for Stage A (Phase 7b). It asks for no permission and opens no
/// camera or picker: it hands back the same sample picture for every source, or fails like an
/// unreadable photo. Phase 22a replaces it with PhotosUI and the camera.
public struct StandInPhotoIntake: PhotoIntake {
    /// The sample picture every source returns. Screens draw it as the piece's placeholder art.
    public static let samplePhoto = PhotoReference.sample("stand-in-photo")

    public var fails: Bool
    public var latency: Duration

    public init(fails: Bool = false, latency: Duration = .zero) {
        self.fails = fails
        self.latency = latency
    }

    public func photo(from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        if Task.isCancelled { throw .cancelled }
        if fails { throw .unreadable }
        return Self.samplePhoto
    }
}
