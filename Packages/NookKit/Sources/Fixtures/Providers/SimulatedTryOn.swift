import Foundation
import Models

/// Stage A's Try it on (RD-06, FR-56): a `.simulated` picture of the look as it is, which the
/// screens draw on the phone from its pieces. It sends nothing and reads no photo. It waits a
/// moment so the making state can be seen, and it can fail on purpose for the error states
/// (`-fixtures demo:offline`, `demo:picture-fails`).
///
/// When she has a try-on photo, a look made of exactly the pieces in one of the sample wardrobe's
/// try-on previews gets that preview, a bundled picture of the person in the example try-on photo
/// wearing it, instead of the drawing (`SampleWardrobe.previewPhoto(for:)`). With no try-on photo,
/// every picture is drawn from the pieces. Both are labelled Simulated.
public struct SimulatedTryOn: TryOnService {
    public enum Mode: Hashable, Sendable {
        case normal
        /// Every picture fails with this error.
        case failing(TryOnError)
    }

    public let mode: Mode
    public let latency: Duration
    /// Whether a look that matches a sample preview gets it.
    public let usesSamplePreviews: Bool
    /// Whether she has a try-on photo now. A sample preview shows the person in it, so without one
    /// the picture is drawn from the pieces.
    private let hasTryOnPhoto: @Sendable () async -> Bool
    private let makeID: @Sendable () -> TryOnPicture.ID

    public init(
        mode: Mode = .normal, latency: Duration = .zero, usesSamplePreviews: Bool = true,
        hasTryOnPhoto: @escaping @Sendable () async -> Bool = { true },
        makeID: @escaping @Sendable () -> TryOnPicture.ID = { .random() }
    ) {
        self.mode = mode
        self.latency = latency
        self.usesSamplePreviews = usesSamplePreviews
        self.hasTryOnPhoto = hasTryOnPhoto
        self.makeID = makeID
    }

    public func makePicture(of look: Look, at date: Date) async throws(TryOnError) -> TryOnPicture {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        if Task.isCancelled { throw .cancelled }
        if case .failing(let error) = mode { throw error }
        var image = TryOnImage.simulated
        if usesSamplePreviews, let preview = SampleWardrobe.previewPhoto(for: look), await hasTryOnPhoto() {
            image = .generated(preview)
        }
        return TryOnPicture(id: makeID(), of: look, image: image, createdAt: date)
    }
}
