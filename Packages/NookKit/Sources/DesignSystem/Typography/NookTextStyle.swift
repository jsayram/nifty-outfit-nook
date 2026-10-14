import SwiftUI

/// The app's text roles, each built on a Dynamic Type text style so it grows with the
/// person's text size setting. There are no fixed point sizes.
///
/// Fonts are Apple system fonts, so nothing is bundled: the rounded design (SF Pro Rounded,
/// the mockups' `--font-ui: ui-rounded`) for the interface, and the serif design (New York,
/// the mockups' `--font-display`) for titles and the name sign.
///
/// Use `.nookTextStyle(.body)` on a view to get the font and its letter spacing, or
/// `Font.nook.body` when only the font is needed.
nonisolated public enum NookTextStyle: String, CaseIterable, Sendable {
    /// Big screen titles (`.title-display`, 33 px serif 800).
    case display
    /// Headings on loading, empty and error states (`.state h1`, 24 px serif 800).
    case title
    /// The open look's title (`.look-title`, 20 px serif 800).
    case lookTitle
    /// Her first name on the wall sign (`.sign .name`, 21 px serif 700 italic).
    case nameSign
    /// Navigation titles and sheet headings (`.nav`, 17 px 700).
    case headline
    /// Body text and row text. The PRD sets body at the standard `.body` size.
    case body
    /// Button labels (`.btn`, 16 px 700).
    case button
    /// Row titles and the results action buttons (`.erow b`, `.grid4 .btn`, 15 px 700).
    case label
    /// Chip labels (`.chip`, 13 px 600).
    case chip
    /// Short explanations under a control (`.ask`, `.req`, `.say`, 13 px 400).
    case note
    /// Tab labels, small tags and marks (`.tabbar`, `.mk`, 12 px 600).
    case caption
    /// Fine print such as "Try-on pictures are simulated." (`.fine`, 11 px 500).
    case finePrint

    /// The Dynamic Type style it scales with.
    public var textStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .title: .title2
        case .lookTitle, .nameSign: .title3
        case .headline: .headline
        case .body: .body
        case .button: .callout
        case .label: .subheadline
        case .chip, .note: .footnote
        case .caption: .caption
        case .finePrint: .caption2
        }
    }

    public var design: Font.Design {
        switch self {
        case .display, .title, .lookTitle, .nameSign: .serif
        default: .rounded
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .title, .lookTitle: .heavy
        case .nameSign, .headline, .button, .label: .bold
        case .chip, .caption: .semibold
        case .finePrint: .medium
        case .body, .note: .regular
        }
    }

    public var isItalic: Bool { self == .nameSign }

    /// Letter spacing in points, from the mockups' `letter-spacing`.
    public var tracking: CGFloat {
        switch self {
        case .display: -0.6
        case .title: -0.3
        case .lookTitle: -0.2
        case .nameSign: 0.2
        default: 0
        }
    }

    /// The size the mockups use at 390 px wide, in points. For reference and tests only; the
    /// real size comes from `textStyle` and the person's text size.
    public var mockupPointSize: CGFloat {
        switch self {
        case .display: 33
        case .title: 24
        case .lookTitle: 20
        case .nameSign: 21
        case .headline: 17
        case .body: 17
        case .button: 16
        case .label: 15
        case .chip, .note: 13
        case .caption: 12
        case .finePrint: 11
        }
    }

    public var font: Font {
        let font = Font.system(textStyle, design: design, weight: weight)
        return isItalic ? font.italic() : font
    }
}

extension Font {
    /// The app's text roles as fonts, for example `Font.nook.body`.
    nonisolated public static let nook = NookFonts()
}

/// Named access to every `NookTextStyle` as a `Font`.
nonisolated public struct NookFonts: Sendable {
    public var display: Font { NookTextStyle.display.font }
    public var title: Font { NookTextStyle.title.font }
    public var lookTitle: Font { NookTextStyle.lookTitle.font }
    public var nameSign: Font { NookTextStyle.nameSign.font }
    public var headline: Font { NookTextStyle.headline.font }
    public var body: Font { NookTextStyle.body.font }
    public var button: Font { NookTextStyle.button.font }
    public var label: Font { NookTextStyle.label.font }
    public var chip: Font { NookTextStyle.chip.font }
    public var note: Font { NookTextStyle.note.font }
    public var caption: Font { NookTextStyle.caption.font }
    public var finePrint: Font { NookTextStyle.finePrint.font }
}

extension View {
    /// Sets the font and letter spacing of one of the app's text roles.
    public func nookTextStyle(_ style: NookTextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }
}
