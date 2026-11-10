import Foundation
import Models

/// The photo step's stand-in for Stage A (Phase 7b). It asks for no permission and opens no
/// camera or picker: it hands back the same example photo for every source, a real photo from
/// the sample wardrobe, or fails like an unreadable photo. Phase 22a replaces it with PhotosUI
/// and the camera.
public struct StandInPhotoIntake: PhotoIntake {
    /// The example photo every source returns: the navy striped tee from the sample wardrobe,
    /// so a piece added in the demo shows a real photo like the rest of the closet. It has no
    /// cutout, so it shows in a tile.
    /// Release builds have no sample photos (Phase 20a), so there the stand-in gives no photo and
    /// the piece shows its drawing.
    #if DEBUG
        public static let samplePhoto = SampleWardrobe.photo("x-striped-tee")
    #else
        public static let samplePhoto = PhotoReference.noPhoto
    #endif

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
        #if DEBUG
            // N4: `-hold photo` keeps the photo step working; `-fail photo` is a photo that couldn't be
            // saved (`-fail photo=unreadable` one that couldn't be read).
            switch await DebugFaults.current.fault(for: ["photo"]) {
            case .cancelled?: throw .cancelled
            case .fail(let failure)?: throw failure.variant == "unreadable" ? .unreadable : .notSaved
            case nil: break
            }
        #endif
        if Task.isCancelled { throw .cancelled }
        if fails { throw .unreadable }
        return Self.samplePhoto
    }
}
