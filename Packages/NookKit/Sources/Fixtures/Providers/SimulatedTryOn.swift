import Foundation
import Models

/// Stage A's Try it on (RD-06, FR-56): a `.simulated` picture of the look as it is, which the
/// screens draw on the phone from its pieces. It sends nothing and reads no photo. It waits a
/// moment so the making state can be seen, and it can fail on purpose for the error states
/// (`-fixtures demo:offline`, `demo:picture-fails`).
///
/// A look made of exactly the pieces in one of the sample wardrobe's try-on previews gets that
/// preview, a bundled picture of the sample woman wearing it, instead of the drawing
/// (`SampleWardrobe.previewPhoto(for:)`). It's still labelled Simulated.
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
    private let makeID: @Sendable () -> TryOnPicture.ID

    public init(
        mode: Mode = .normal, latency: Duration = .zero, usesSamplePreviews: Bool = true,
        makeID: @escaping @Sendable () -> TryOnPicture.ID = { .random() }
    ) {
        self.mode = mode
        self.latency = latency
        self.usesSamplePreviews = usesSamplePreviews
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
        let image: TryOnImage =
            usesSamplePreviews
            ? SampleWardrobe.previewPhoto(for: look).map { .generated($0) } ?? .simulated : .simulated
        return TryOnPicture(id: makeID(), of: look, image: image, createdAt: date)
    }
}
