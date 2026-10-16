import Testing

@testable import Models

struct CutoutThresholdsTests {
    private let thresholds = CutoutThresholds.proposed

    private func quality(
        instances: Int = 1, coverage: Double = 0.3, largest: Double = 1, edges: CutoutEdges = [], soft: Double = 0.05
    ) -> CutoutQuality {
        CutoutQuality(
            instanceCount: instances, coverage: coverage, largestInstanceShare: largest, touchedEdges: edges,
            softEdgeRatio: soft, subjectBounds: .whole)
    }

    @Test func aCleanSingleGarmentIsASticker() {
        #expect(thresholds.concerns(with: quality()).isEmpty)
        #expect(thresholds.suggestsSticker(quality()))
    }

    @Test func eachSignalHasItsOwnConcern() {
        #expect(thresholds.concerns(with: quality(coverage: 0.01)) == [.tooSmall])
        #expect(thresholds.concerns(with: quality(coverage: 0.97)) == [.tooLarge])
        #expect(thresholds.concerns(with: quality(instances: 3, largest: 0.5)) == [.severalSubjects])
        #expect(thresholds.concerns(with: quality(edges: [.bottom, .left])) == [.runsOffThePhoto])
        #expect(thresholds.concerns(with: quality(soft: 0.4)) == [.unsureEdges])
    }

    @Test func limitsAreInclusive() {
        #expect(thresholds.suggestsSticker(quality(coverage: thresholds.minimumCoverage)))
        #expect(thresholds.suggestsSticker(quality(coverage: thresholds.maximumCoverage)))
        #expect(thresholds.suggestsSticker(quality(soft: thresholds.maximumSoftEdgeRatio)))
        #expect(thresholds.suggestsSticker(quality(instances: 2, largest: thresholds.minimumLargestInstanceShare)))
    }

    /// A hanger or a tag lifted with the garment is fine when the garment clearly dominates, and
    /// one touched edge (a hanger hook, a sleeve at the border) is allowed.
    @Test func smallExtrasAndOneEdgeAreAllowed() {
        #expect(thresholds.suggestsSticker(quality(instances: 2, largest: 0.95)))
        #expect(thresholds.suggestsSticker(quality(edges: [.top])))
    }

    @Test func everyConcernIsListed() {
        let worst = quality(instances: 4, coverage: 0.02, largest: 0.3, edges: [.top, .bottom, .left], soft: 0.6)
        #expect(Set(thresholds.concerns(with: worst)) == [.tooSmall, .severalSubjects, .runsOffThePhoto, .unsureEdges])
    }

    @Test func edgesCount() {
        #expect(CutoutEdges().count == 0)
        #expect(CutoutEdges([.top, .right]).count == 2)
        #expect(CutoutEdges([.top, .bottom, .left, .right]).count == 4)
    }
}
