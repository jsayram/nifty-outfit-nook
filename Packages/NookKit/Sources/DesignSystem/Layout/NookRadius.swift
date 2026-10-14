import SwiftUI

/// Corner radii from `css/soft.css`. The soft style uses larger radii than the first mockups.
/// Always draw them with `.continuous` corners, through `NookRadius.shape(_:)`.
///
/// Chips, tags and pills are capsules (`border-radius: 999px`): use `Capsule()`, not a radius.
nonisolated public enum NookRadius {
    /// Small labels such as "Simulated" (`.sim`, 10 px).
    public static let small: CGFloat = 10
    /// Slim plates (`.tag.slim`, 14 px).
    public static let plateSlim: CGFloat = 14
    /// Small buttons and the results action buttons (`.btn.small`, `.grid4 .btn`, 16 px).
    public static let buttonSmall: CGFloat = 16
    /// Buttons and plates that sit on art (`.btn`, `.tag`, 18 px). Gently rounded, not pills.
    public static let button: CGFloat = 18
    /// Soft groups: the version switch, the piece list, rows on a tint (22 px).
    public static let group: CGFloat = 22
    /// Room tiles in Closet (`.tile`, 24 px).
    public static let tile: CGFloat = 24
    /// Sheets and the large-text rows (28 px).
    public static let sheet: CGFloat = 28

    /// A rounded rectangle with continuous corners.
    public static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
