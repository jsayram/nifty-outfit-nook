import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

@MainActor
struct TypographyTests {
    /// At the default text size, each role's text style lands within 2 points of the size the
    /// mockups use, apart from body, which the PRD sets at the standard `.body` size.
    @Test(arguments: NookTextStyle.allCases)
    func defaultSizeIsCloseToTheMockup(style: NookTextStyle) {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let size = UIFont.preferredFont(forTextStyle: style.textStyle.uiKit, compatibleWith: traits).pointSize
        #expect(abs(size - style.mockupPointSize) <= 2, "\(style) is \(size) pt, mockup \(style.mockupPointSize)")
    }

    /// Every role grows with the person's text size setting.
    @Test(arguments: NookTextStyle.allCases)
    func scalesWithDynamicType(style: NookTextStyle) {
        func size(_ category: UIContentSizeCategory) -> CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            return UIFont.preferredFont(forTextStyle: style.textStyle.uiKit, compatibleWith: traits).pointSize
        }
        #expect(size(.accessibilityExtraExtraExtraLarge) > size(.large))
        // iOS keeps the smallest styles at 11 pt, so they don't shrink below the default.
        #expect(size(.large) >= size(.extraSmall))
    }

    @Test func serifIsOnlyForTitlesAndTheNameSign() {
        let serif = NookTextStyle.allCases.filter { $0.design == .serif }
        #expect(serif == [.display, .title, .lookTitle, .nameSign])
    }

    @Test func onlyTheNameSignIsItalic() {
        #expect(NookTextStyle.allCases.filter(\.isItalic) == [.nameSign])
    }

    @Test func bodyUsesTheStandardBodyStyle() {
        #expect(NookTextStyle.body.textStyle == .body)
        #expect(NookTextStyle.body.weight == .regular)
    }
}

extension Font.TextStyle {
    fileprivate var uiKit: UIFont.TextStyle {
        switch self {
        case .extraLargeTitle: .extraLargeTitle
        case .extraLargeTitle2: .extraLargeTitle2
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
