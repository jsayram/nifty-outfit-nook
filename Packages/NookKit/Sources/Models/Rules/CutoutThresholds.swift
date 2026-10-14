import Foundation

/// Proposed limits for when a cutout is clean enough to show as a sticker (RD-07). Anything
/// else shows as the rounded photo tile (RD-07.2).
///
/// These are a starting point from Phase 8a, not a decision. Phase 8b sets the real values from
/// the benchmark on Lily's iPhone 12 and real garment photos (`docs/cutout-feasibility.md`).
public struct CutoutThresholds: Hashable, Sendable {
    /// Below this the subject is too small to be the garment, or Vision picked up a speck.
    public var minimumCoverage: Double
    /// Above this the "subject" is most of the photo, so the background was probably lifted too.
    public var maximumCoverage: Double
    /// With several subjects, the largest must be at least this share of everything lifted.
    public var minimumLargestInstanceShare: Double
    /// A subject touching more edges than this runs off the photo.
    public var maximumTouchedEdges: Int
    /// Above this share of soft mask the edges are too unsure for a clean outline.
    public var maximumSoftEdgeRatio: Double

    public init(
        minimumCoverage: Double,
        maximumCoverage: Double,
        minimumLargestInstanceShare: Double,
        maximumTouchedEdges: Int,
        maximumSoftEdgeRatio: Double
    ) {
        self.minimumCoverage = minimumCoverage
        self.maximumCoverage = maximumCoverage
        self.minimumLargestInstanceShare = minimumLargestInstanceShare
        self.maximumTouchedEdges = maximumTouchedEdges
        self.maximumSoftEdgeRatio = maximumSoftEdgeRatio
    }

    /// The Phase 8a proposal.
    public static let proposed = CutoutThresholds(
        minimumCoverage: 0.05,
        maximumCoverage: 0.90,
        minimumLargestInstanceShare: 0.80,
        maximumTouchedEdges: 1,
        maximumSoftEdgeRatio: 0.25
    )

    /// Why a cutout falls back to the tile.
    public enum Concern: String, Hashable, Sendable, CaseIterable {
        case tooSmall
        case tooLarge
        case severalSubjects
        case runsOffThePhoto
        case unsureEdges
    }

    /// Every concern with this cutout. Empty means it can be a sticker.
    public func concerns(with quality: CutoutQuality) -> [Concern] {
        var concerns: [Concern] = []
        if quality.coverage < minimumCoverage { concerns.append(.tooSmall) }
        if quality.coverage > maximumCoverage { concerns.append(.tooLarge) }
        if quality.instanceCount > 1 && quality.largestInstanceShare < minimumLargestInstanceShare {
            concerns.append(.severalSubjects)
        }
        if quality.touchedEdges.count > maximumTouchedEdges { concerns.append(.runsOffThePhoto) }
        if quality.softEdgeRatio > maximumSoftEdgeRatio { concerns.append(.unsureEdges) }
        return concerns
    }

    public func suggestsSticker(_ quality: CutoutQuality) -> Bool {
        concerns(with: quality).isEmpty
    }
}
