/// Every semantic colour in the app. Each one is a colour set of the same name in
/// `Resources/Colors.xcassets`, with a light and a dark appearance.
///
/// The values live in `Palette.swift`. Use them in views through `Color.nook`, for example
/// `.foregroundStyle(Color.nook.textPrimary)`. The CSS each token comes from is listed in
/// `DesignSystem/README.md`.
///
/// There are no border or outline tokens on purpose. Cards, rows, tiles, chips and plates have
/// no stroke (the soft no-box style). Separation comes from space, tints and soft shadows.
nonisolated public enum ColorToken: String, CaseIterable, Sendable {
    // MARK: Interface

    /// The main screen background, also the bedroom wall. Top of the wall gradient.
    case background
    /// The bottom of the wall gradient, a little deeper than `background`.
    case backgroundLow
    /// Plates, sheets and input fields. Near white in light, a raised espresso in dark.
    case surface
    /// A see-through wash for quiet chips, soft rows and ghost buttons.
    case tint
    /// A stronger wash for plates that sit on drawn art, so text stays readable.
    case tintStrong
    /// Headings, body text and important labels.
    case textPrimary
    /// Supporting explanations and metadata.
    case textSecondary
    /// The espresso accent: selected chips, primary buttons, links and accent icons.
    /// In dark appearance it turns into a light latte so it works for text and fills alike.
    case accent
    /// The accent when pressed.
    case accentPressed
    /// Text and icons on an `accent` fill.
    case onAccent
    /// Quiet emphasis: saved state, small marks, the soft accent wash.
    case accentSoft
    /// Disclosure chevrons at the end of rows.
    case chevron
    /// The empty part of meters and progress tracks.
    case track
    /// The colour of the fading divider between groups. Decorative only: never the only
    /// boundary of a control.
    case divider
    /// The colour of the small soft shadow that falls below chips, plates and rows.
    case shadow
    /// The colour of the larger soft shadow under buttons and big rows.
    case shadowLarge

    // MARK: Status

    /// Successful saves and "already own". Never the only signal: always with text or an icon.
    case success
    /// The background of success badges and notes.
    case successSurface
    /// Gentle warnings, like the laundry note or a partial result.
    case warning
    /// The background of warning notes.
    case warningSurface
    /// Errors, destructive actions and validation text.
    case error
    /// The background of error notes.
    case errorSurface

    // MARK: Room and art

    /// The bedroom floor, top of its gradient.
    case floor
    /// The bottom of the floor gradient.
    case floorLow
    /// The line where the wall meets the floor.
    case floorLine
    /// Sage in the drawn room (plants, the cardigan, soft furnishings).
    case artSage
    /// Deeper sage for shading.
    case artSageDeep
    /// Sage outlines inside drawings.
    case artSageLine
    /// Sand, which replaces the old pink in the drawn room.
    case artSand
    /// Stone, which replaces the old lilac in the drawn room.
    case artStone
    /// Butter yellow in the drawn room.
    case artButter
    /// Butter outlines inside drawings.
    case artButterLine
    /// The painted panel of the name sign on the wall.
    case signPanel
    /// Her name, written on the sign's panel.
    case signText

    /// Where the token is used, for grouping in docs and the catalog.
    public enum Group: String, CaseIterable, Sendable {
        case interface
        case status
        case room
    }

    public var group: Group {
        switch self {
        case .success, .successSurface, .warning, .warningSurface, .error, .errorSurface:
            .status
        case .floor, .floorLow, .floorLine, .artSage, .artSageDeep, .artSageLine, .artSand, .artStone, .artButter,
            .artButterLine, .signPanel, .signText:
            .room
        default:
            .interface
        }
    }

    /// The colour set's name in `Colors.xcassets`.
    public var assetName: String { rawValue }

    /// The light and dark values from `Palette`.
    public var value: TokenValue { Palette.value(for: self) }
}
