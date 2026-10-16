/// A colour pairing the app relies on, with the WCAG contrast it must reach in both appearances.
///
/// PRD section 7.1: 4.5:1 for normal text, 3:1 for large text and for icons, control
/// boundaries and focus indicators. `ContrastTests` checks every entry in
/// `ContrastRequirement.all` in light and dark.
nonisolated public struct ContrastRequirement: Hashable, Sendable, CustomStringConvertible {
    nonisolated public enum Kind: Hashable, Sendable {
        /// Normal-size text: 4.5:1.
        case text
        /// Large text, icons and control boundaries: 3:1.
        case largeTextOrGraphic

        public var minimum: Double {
            switch self {
            case .text: 4.5
            case .largeTextOrGraphic: 3
            }
        }
    }

    public let foreground: ColorToken
    public let background: ColorToken
    /// The opaque colour under a see-through `background`, such as the wall under a tint.
    public let base: ColorToken?
    public let kind: Kind

    public init(_ foreground: ColorToken, on background: ColorToken, over base: ColorToken? = nil, kind: Kind) {
        self.foreground = foreground
        self.background = background
        self.base = base
        self.kind = kind
    }

    public var minimum: Double { kind.minimum }

    /// The contrast ratio of this pairing in one appearance, after blending any see-through
    /// colours onto what's under them.
    public func ratio(in appearance: Appearance) -> Double {
        var under = background.value[appearance]
        if let base {
            under = under.composited(over: base.value[appearance])
        }
        var over = foreground.value[appearance]
        if !over.isOpaque {
            over = over.composited(over: under)
        }
        return RGBA.contrastRatio(over, under)
    }

    public var description: String {
        let place = base.map { "\(background.rawValue) over \($0.rawValue)" } ?? background.rawValue
        return "\(foreground.rawValue) on \(place)"
    }
}

extension ContrastRequirement {
    /// Every pairing the design relies on. Add a line here whenever a new pairing appears.
    public static let all: [ContrastRequirement] = textPairs + statusPairs + graphicPairs

    /// The places text sits: plain backgrounds, and the see-through tints over the wall
    /// (both ends of its gradient) and over the floor.
    private static let textBackgrounds: [(ColorToken, ColorToken?)] = [
        (.background, nil), (.backgroundLow, nil), (.surface, nil), (.accentSoft, nil),
        (.tint, .background), (.tint, .backgroundLow), (.tint, .floor),
        (.tintStrong, .background), (.tintStrong, .backgroundLow), (.tintStrong, .floor),
        // A quick tour's card (Phase 16a).
        (.tourCard, nil),
    ]

    private static let textPairs: [ContrastRequirement] =
        [ColorToken.textPrimary, .textSecondary, .accent].flatMap { text in
            textBackgrounds.map { ContrastRequirement(text, on: $0.0, over: $0.1, kind: .text) }
        } + [
            // Primary text straight on the floor and on the status notes.
            // Secondary text never sits straight on the floor: it's 4.4:1 there, so it goes on a tint.
            ContrastRequirement(.textPrimary, on: .floor, kind: .text),
            ContrastRequirement(.textPrimary, on: .floorLow, kind: .text),
            ContrastRequirement(.textPrimary, on: .successSurface, kind: .text),
            ContrastRequirement(.textPrimary, on: .warningSurface, kind: .text),
            // The caption on a butter row (Home's Occasion row at large text sizes, Phase 5b).
            ContrastRequirement(.textSecondary, on: .warningSurface, kind: .text),
            ContrastRequirement(.textPrimary, on: .errorSurface, kind: .text),
            // Selected chips, primary buttons and the active tab.
            ContrastRequirement(.onAccent, on: .accent, kind: .text),
            ContrastRequirement(.onAccent, on: .accentPressed, kind: .text),
            // Her name on the sign.
            ContrastRequirement(.signText, on: .signPanel, kind: .text),
            // Components (Phase 2b): a pressed soft or pill button, the toast, and the action
            // button inside a banner.
            ContrastRequirement(.accentPressed, on: .track, kind: .text),
            ContrastRequirement(.background, on: .textPrimary, kind: .text),
            ContrastRequirement(.accent, on: .tintStrong, over: .warningSurface, kind: .text),
            // Delete my data's button: words on the error colour (Phase 14b).
            ContrastRequirement(.onAccent, on: .error, kind: .text),
        ]

    private static let statusPairs: [ContrastRequirement] = [
        (ColorToken.success, ColorToken.successSurface), (.warning, .warningSurface), (.error, .errorSurface),
    ].flatMap { status, surface in
        [surface, .background, .backgroundLow, .surface].map { ContrastRequirement(status, on: $0, kind: .text) }
    }

    private static let graphicPairs: [ContrastRequirement] =
        [
            // A selected chip or primary button is told apart from the wall and floor by its fill.
            ContrastRequirement(.accent, on: .background, kind: .largeTextOrGraphic),
            ContrastRequirement(.accent, on: .backgroundLow, kind: .largeTextOrGraphic),
            ContrastRequirement(.accent, on: .floor, kind: .largeTextOrGraphic),
            // The filled part of a meter against its track.
            ContrastRequirement(.accent, on: .track, kind: .largeTextOrGraphic),
            // Icons on a butter row (Phase 5b).
            ContrastRequirement(.accent, on: .warningSurface, kind: .largeTextOrGraphic),
            // Delete my data's button stands out from the floor by its fill (Phase 14b).
            ContrastRequirement(.error, on: .floor, kind: .largeTextOrGraphic),
        ]
        + [ColorToken.background, .backgroundLow, .surface].map {
            ContrastRequirement(.chevron, on: $0, kind: .largeTextOrGraphic)
        }
}
