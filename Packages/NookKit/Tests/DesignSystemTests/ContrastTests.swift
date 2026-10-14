import Testing

@testable import DesignSystem

/// PRD section 7.1 and LR-02.2: every text and control pairing meets 4.5:1 (normal text) or
/// 3:1 (large text, icons and control boundaries) in light and dark.
struct ContrastTests {
    @Test(arguments: Appearance.allCases)
    func everyRequiredPairingMeetsItsMinimum(appearance: Appearance) {
        for requirement in ContrastRequirement.all {
            let ratio = requirement.ratio(in: appearance)
            #expect(
                ratio >= requirement.minimum,
                "\(requirement) in \(appearance.rawValue) is \(ratio), needs \(requirement.minimum)"
            )
        }
    }

    @Test func coversTheMainTextColoursOnEveryBackground() {
        let pairs = Set(ContrastRequirement.all.map { "\($0.foreground.rawValue)/\($0.background.rawValue)" })
        for text in ["textPrimary", "textSecondary", "accent"] {
            for background in ["background", "backgroundLow", "surface", "tint", "tintStrong", "accentSoft"] {
                #expect(pairs.contains("\(text)/\(background)"), "missing \(text) on \(background)")
            }
        }
        #expect(pairs.contains("onAccent/accent"))
    }

    @Test func seeThroughBackgroundsAreCheckedOverWhatIsUnderThem() {
        for requirement in ContrastRequirement.all {
            for appearance in Appearance.allCases where !requirement.background.value[appearance].isOpaque {
                #expect(requirement.base != nil, "\(requirement) needs a base colour under its tint")
            }
        }
    }

    /// Secondary text is kept off the bare floor on purpose. If this starts passing, the floor or
    /// the text changed, and the rule in ContrastRequirement can be relaxed.
    @Test func secondaryTextOnTheBareFloorIsTooLow() {
        let pairing = ContrastRequirement(.textSecondary, on: .floor, kind: .text)
        #expect(pairing.ratio(in: .light) < 4.5)
    }
}
