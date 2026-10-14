import CoreGraphics

/// Spacing in points. An 8 point rhythm with 4 point half steps, as in PRD section 7.1.
/// In the soft style, space is what separates things, so use these instead of lines.
nonisolated public enum NookSpacing {
    public static let xxSmall: CGFloat = 2
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 20
    public static let xxLarge: CGFloat = 24
    public static let xxxLarge: CGFloat = 32

    /// Every step, smallest first.
    public static let scale: [CGFloat] = [xxSmall, xSmall, small, medium, large, xLarge, xxLarge, xxxLarge]

    /// Left and right screen margin (the mockups' 16 px gutters).
    public static let screenMargin: CGFloat = large
    /// Padding inside soft groups and sheets.
    public static let groupPadding: CGFloat = large
    /// Space between groups of rows, where a box would otherwise go.
    public static let groupGap: CGFloat = xxLarge
    /// Space between chips in a row of filters.
    public static let chipGap: CGFloat = small

    /// The smallest tap target, in both directions (Apple's 44 point minimum).
    public static let minimumTapTarget: CGFloat = 44
}
