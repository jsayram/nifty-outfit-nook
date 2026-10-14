import Foundation
import ImageIO
import Models

/// The cutout step's stand-in for Stage A screens and tests (Phase 8a). It lifts nothing: it
/// hands the photo back as it came, with the quality signals it was given, or fails the way it
/// was told to. The real one is `VisionCutoutService` in the `Services` module.
public struct StandInCutoutService: CutoutService {
    public enum Outcome: Hashable, Sendable {
        /// Returns the photo with these signals.
        case lifted(CutoutQuality)
        case fails(CutoutError)
    }

    /// Signals for a clean single garment, well inside `CutoutThresholds.proposed`.
    public static let cleanQuality = CutoutQuality(
        instanceCount: 1,
        coverage: 0.4,
        largestInstanceShare: 1,
        touchedEdges: [],
        softEdgeRatio: 0.05,
        subjectBounds: CutoutBounds(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
    )

    public var outcome: Outcome
    public var latency: Duration

    public init(outcome: Outcome = .lifted(Self.cleanQuality), latency: Duration = .zero) {
        self.outcome = outcome
        self.latency = latency
    }

    public func cutout(from imageData: Data) async throws(CutoutError) -> CutoutResult {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        if Task.isCancelled { throw .cancelled }
        switch outcome {
        case .fails(let error):
            throw error
        case .lifted(let quality):
            guard let size = Self.pixelSize(of: imageData) else { throw .unreadableImage }
            return CutoutResult(
                imageData: imageData, pixelWidth: size.width, pixelHeight: size.height, quality: quality)
        }
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
