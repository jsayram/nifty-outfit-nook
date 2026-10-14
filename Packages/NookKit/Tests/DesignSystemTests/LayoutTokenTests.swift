import CoreGraphics
import Testing

@testable import DesignSystem

struct LayoutTokenTests {
    @Test func spacingScaleClimbsInEvenSteps() {
        let scale = NookSpacing.scale
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
        for step in scale {
            #expect(step.truncatingRemainder(dividingBy: 2) == 0, "\(step) is off the 2 point grid")
        }
        #expect(NookSpacing.screenMargin == 16)
    }

    @Test func tapTargetsAreAtLeast44Points() {
        #expect(NookSpacing.minimumTapTarget >= 44)
    }

    @Test func radiiMatchTheSoftStyle() {
        let radii = [
            NookRadius.small, NookRadius.plateSlim, NookRadius.buttonSmall, NookRadius.button, NookRadius.group,
            NookRadius.tile, NookRadius.sheet,
        ]
        #expect(radii == [10, 14, 16, 18, 22, 24, 28])
    }

    @Test func shadowsMatchTheCSS() {
        #expect(SoftShadow.drop == SoftShadow(color: .shadow, offsetY: 10, blur: 16, spread: -12))
        #expect(SoftShadow.dropLarge == SoftShadow(color: .shadowLarge, offsetY: 16, blur: 22, spread: -16))
    }

    @Test(arguments: [SoftShadow.drop, SoftShadow.dropLarge])
    func shadowsFallOnlyBelow(shadow: SoftShadow) {
        #expect(shadow.offsetY > 0)
        #expect(shadow.spread < 0)
        #expect(shadow.topClearance > 0)
    }
}
