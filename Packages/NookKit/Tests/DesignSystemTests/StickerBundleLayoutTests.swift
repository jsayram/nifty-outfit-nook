import CoreGraphics
import Testing

@testable import DesignSystem

/// The look bundle's flat-lay arrangement (Phase 9, RD-07.1): every piece inside the box,
/// overlaps within the limit, the same placements for the same look, and sensible stacking.
@Suite
struct StickerBundleLayoutTests {
    /// Every mix of 2 to 6 pieces, kinds repeating (1,708 of them), so odd looks are covered
    /// too: two tops, a dress and trousers, three bags.
    static let everyMix: [[BundleRole]] = {
        var mixes: [[BundleRole]] = []
        func grow(from start: Int, _ mix: [BundleRole]) {
            if mix.count >= 2 { mixes.append(mix) }
            guard mix.count < 6 else { return }
            for next in start..<BundleRole.allCases.count {
                grow(from: next, mix + [BundleRole.allCases[next]])
            }
        }
        grow(from: 0, [])
        return mixes
    }()

    static let seeds = ["o-interview", "o-brunch-idea", "8f14e45f-ceea-467f-a0e6-a7f2c1b8d0e3"]

    static let box = CGRect(origin: .zero, size: StickerBundleLayout.designSize)

    @Test func coversEveryMix() {
        #expect(Self.everyMix.count == 1_708)
    }

    @Test func everyPieceIsInsideTheBoxTiltIncluded() {
        for mix in Self.everyMix {
            for seed in Self.seeds {
                for placement in StickerBundleLayout.place(mix, seed: seed) {
                    let tilted = StickerBundleLayout.rotatedBounds(placement.frame, degrees: placement.angle)
                    #expect(
                        Self.box.insetBy(dx: -0.01, dy: -0.01).contains(tilted),
                        "\(mix) with seed \(seed): \(placement.frame) tilted \(placement.angle)° leaves the box")
                }
            }
        }
    }

    @Test func noTwoPiecesOverlapBeyondTheLimit() {
        var worst: CGFloat = 0
        for mix in Self.everyMix {
            for seed in Self.seeds {
                let placements = StickerBundleLayout.place(mix, seed: seed)
                for (offset, first) in placements.enumerated() {
                    for second in placements[(offset + 1)...] {
                        let overlap = StickerBundleLayout.overlap(first.frame, second.frame)
                        worst = max(worst, overlap)
                        #expect(
                            overlap <= StickerBundleLayout.maximumOverlap,
                            "\(mix) with seed \(seed): pieces \(first.index) and \(second.index) overlap \(overlap)")
                    }
                }
            }
        }
        // The pieces are meant to touch and overlap a little, as in the mockups.
        #expect(worst > 0.1)
    }

    @Test func onePlacementPerPieceInOrder() {
        for mix in Self.everyMix {
            let placements = StickerBundleLayout.place(mix, seed: "o-interview")
            #expect(placements.map(\.index) == Array(mix.indices))
            #expect(placements.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        }
    }

    @Test func noPiecesNoPlacements() {
        #expect(StickerBundleLayout.place([], seed: "x").isEmpty)
    }

    @Test func sameLookSamePlacements() {
        let outfit: [BundleRole] = [.layer, .top, .bottom, .shoes, .bag]
        let first = StickerBundleLayout.place(outfit, seed: "o-interview")
        for _ in 0..<5 {
            #expect(StickerBundleLayout.place(outfit, seed: "o-interview") == first)
        }
    }

    /// Fixed numbers, so a change to the seed's arithmetic (or a switch to Swift's `Hasher`, which
    /// changes every launch) shows up as a failure instead of looks quietly moving.
    @Test func seedIsStableAcrossLaunches() {
        var seed = BundleSeed("o-interview")
        #expect(seed.next() == 0x73af_18de_24fe_922f)
        let placement = StickerBundleLayout.place([.top, .bottom], seed: "o-interview")[0]
        #expect(abs(placement.angle - (-3.0)) < 2.6)
    }

    @Test func differentLooksTiltDifferently() {
        let outfit: [BundleRole] = [.top, .bottom, .shoes]
        let angles = Set(
            ["o-interview", "o-weekend", "o-lace-date", "o-blazer-office"].map { seed in
                StickerBundleLayout.place(outfit, seed: seed).map { ($0.angle * 100).rounded() }
            })
        #expect(angles.count == 4)
    }

    @Test func tiltsStaySlight() {
        for mix in Self.everyMix {
            for placement in StickerBundleLayout.place(mix, seed: "o-weekend") {
                #expect(abs(placement.angle) <= 11, "\(mix): \(placement.angle)°")
            }
        }
    }

    /// Worn order, top to bottom: tops above trousers, trousers above shoes.
    @Test func piecesLieWhereTheyAreWorn() {
        let roles: [BundleRole] = [.layer, .top, .bottom, .shoes, .bag]
        for seed in Self.seeds {
            let placements = StickerBundleLayout.place(roles, seed: seed)
            let layer = placements[0].frame
            let top = placements[1].frame
            let bottom = placements[2].frame
            let shoes = placements[3].frame
            let bag = placements[4].frame
            #expect(top.midY < bottom.midY && layer.midY < bottom.midY)
            #expect(bottom.midY < shoes.midY)
            // The layer on the left, the top on the right, the bag at the right side.
            #expect(layer.midX < top.midX)
            #expect(bag.midX > bottom.midX)
        }
    }

    @Test func shoesAndTopsAreDrawnOverTheTrousers() {
        let placements = StickerBundleLayout.place([.bottom, .top, .shoes, .layer], seed: "o-interview")
        let z = Dictionary(uniqueKeysWithValues: placements.map { ($0.index, $0.zIndex) })
        #expect(z[2]! > z[0]!, "Shoes over the trousers' hem")
        #expect(z[1]! > z[0]!, "The top's hem over the trousers")
        #expect(z[1]! > z[3]!, "The top over the layer")
    }

    @Test func aDressTakesTheMiddleWithALayerBesideIt() {
        let placements = StickerBundleLayout.place([.dress, .layer, .shoes], seed: "o-lace-date")
        let dress = placements[0].frame
        let layer = placements[1].frame
        #expect(dress.height > Self.box.height * 0.6)
        #expect(layer.midX > dress.midX && layer.midY < dress.midY)
        #expect(placements[1].zIndex > placements[0].zIndex)
    }

    /// A small look grows to fill the box, but only so far.
    @Test func smallLooksFillTheBox() {
        let placements = StickerBundleLayout.place([.top, .bottom], seed: "o-interview")
        let bounds = placements.map { StickerBundleLayout.rotatedBounds($0.frame, degrees: $0.angle) }
            .reduce(CGRect.null) { $0.union($1) }
        #expect(bounds.height > Self.box.height * 0.9 || bounds.width > Self.box.width * 0.9)
        #expect(abs(bounds.midX - Self.box.midX) < 0.5 && abs(bounds.midY - Self.box.midY) < 0.5)
    }

    @Test func overlapIsAShareOfTheSmallerFrame() {
        let big = CGRect(x: 0, y: 0, width: 100, height: 100)
        let small = CGRect(x: 90, y: 90, width: 20, height: 20)
        #expect(abs(StickerBundleLayout.overlap(big, small) - 0.25) < 0.0001)
        #expect(StickerBundleLayout.overlap(big, CGRect(x: 200, y: 0, width: 10, height: 10)) == 0)
        #expect(StickerBundleLayout.overlap(big, big) == 1)
    }

    @Test func rotatedBoundsGrowWithTheTilt() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(StickerBundleLayout.rotatedBounds(frame, degrees: 0) == frame)
        let turned = StickerBundleLayout.rotatedBounds(frame, degrees: 90)
        #expect(abs(turned.width - 50) < 0.001 && abs(turned.height - 100) < 0.001)
        #expect(abs(turned.midX - 50) < 0.001 && abs(turned.midY - 25) < 0.001)
    }

    @Test func framesScaleWithTheBundleWidth() {
        let placement = BundlePlacement(
            index: 0, frame: CGRect(x: 30, y: 60, width: 150, height: 120), angle: 3, zIndex: 0)
        #expect(placement.frame(forWidth: 150) == CGRect(x: 15, y: 30, width: 75, height: 60))
        #expect(placement.frame(forWidth: 300) == placement.frame)
    }

    /// The whole check for every mix runs in well under a frame per look.
    @Test func placingIsQuick() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for mix in Self.everyMix { _ = StickerBundleLayout.place(mix, seed: "o-interview") }
        }
        #expect(elapsed < .seconds(10), "Placing 1,708 looks took \(elapsed)")
    }
}
