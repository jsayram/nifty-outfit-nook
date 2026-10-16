import CoreGraphics
import Testing

@testable import DesignSystem

/// Where a quick tour's card goes (Phase 16a, PRD §7.8): never over the control it points at,
/// on the roomier side, and on its own when nothing fits.
@MainActor
struct TourPlacementTests {
    /// An iPhone 17's screen inside its safe area and 16-point margins.
    static let area = CGRect(x: 16, y: 78, width: 370, height: 746)
    static let card = CGSize(width: 300, height: 180)

    @Test func belowAControlNearTheTop() throws {
        let sign = CGRect(x: 290, y: 250, width: 100, height: 60)
        let placement = NookTourPlacement.place(card: Self.card, target: sign, in: Self.area)
        #expect(placement.tailEdge == .top)
        #expect(placement.card.minY >= sign.maxY + NookTourPlacement.spotlightPadding)
        #expect(Self.area.contains(placement.card))
        #expect(!placement.card.intersects(try #require(placement.spotlight)))
        // The tail aims at the control, kept off the card's corners.
        let tail = try #require(placement.tailPosition)
        #expect(tail <= placement.card.maxX - NookTourPlacement.tailInset)
        #expect(abs(tail - sign.midX) < 30)
    }

    @Test func aboveAControlNearTheBottom() {
        let suitcase = CGRect(x: 4, y: 600, width: 112, height: 190)
        let placement = NookTourPlacement.place(card: Self.card, target: suitcase, in: Self.area)
        #expect(placement.tailEdge == .bottom)
        #expect(placement.card.maxY <= suitcase.minY)
        #expect(Self.area.contains(placement.card))
    }

    /// A tall control on a wide screen: neither above nor below fits, so the card goes beside.
    @Test func besideATallControlOnAWideScreen() {
        let area = CGRect(x: 16, y: 40, width: 1178, height: 760)
        let wardrobe = CGRect(x: 60, y: 60, width: 220, height: 720)
        let placement = NookTourPlacement.place(card: Self.card, target: wardrobe, in: area)
        #expect(placement.tailEdge == .leading)
        #expect(placement.card.minX >= wardrobe.maxX)
        #expect(area.contains(placement.card))
    }

    /// At the largest text sizes the card fits nowhere clear of the control: it shows on its
    /// own, with no spotlight and no tail.
    @Test func onItsOwnWhenItWouldCoverTheControl() {
        let row = CGRect(x: 16, y: 300, width: 370, height: 120)
        let placement = NookTourPlacement.place(
            card: CGSize(width: 370, height: 640), target: row, in: Self.area)
        #expect(placement.spotlight == nil)
        #expect(placement.tailEdge == nil)
        #expect(Self.area.contains(placement.card))
    }

    /// No control (missing, or out of sight): the card in the middle, no spotlight.
    @Test func inTheMiddleWithNoControl() {
        let placement = NookTourPlacement.place(card: Self.card, target: nil, in: Self.area)
        #expect(placement.spotlight == nil)
        #expect(placement.tailEdge == nil)
        #expect(placement.card.midX == Self.area.midX)
        #expect(placement.card.midY == Self.area.midY)
    }

    /// A card taller or wider than the screen is cut to it.
    @Test func neverBiggerThanTheScreen() {
        let placement = NookTourPlacement.place(
            card: CGSize(width: 480, height: 2000), target: nil, in: Self.area)
        #expect(placement.card.size == Self.area.size)
    }

    @Test func theCardGrowsWithTheTextSize() {
        #expect(NookTourOverlay.cardWidth(for: .large) == 300)
        #expect(NookTourOverlay.cardWidth(for: .xxxLarge) == 340)
        #expect(NookTourOverlay.cardWidth(for: .accessibility5) == 480)
    }

    @Test func voiceOverReadsTheStepTheWordsAndTheControl() {
        let step = NookTourStep(
            title: "Style Me", message: "Tap the laptop.", index: 0, count: 4, finishTitle: "Start styling",
            targetLabel: "Laptop: Style Me")
        #expect(
            NookTourCard.spokenWords(for: step)
                == "Quick tour, step 1 of 4. Style Me. Tap the laptop. Highlighted: Laptop: Style Me.")
    }
}
