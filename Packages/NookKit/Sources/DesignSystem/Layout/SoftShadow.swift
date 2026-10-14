import SwiftUI

/// A shadow that falls only below a shape, never around it (the soft style's `--soft-drop`).
///
/// CSS gets this with a negative spread: `0 10px 16px -12px`. SwiftUI's `.shadow` has no
/// spread, so it would put a halo on every side. `softShadow(_:in:)` draws the CSS version
/// instead: the shape, shrunk by the spread, moved down, blurred, and cut away where the
/// shape itself is, so a see-through tint on top doesn't turn muddy.
nonisolated public struct SoftShadow: Hashable, Sendable {
    /// The shadow's colour, which carries its opacity in both appearances.
    public let color: ColorToken
    /// How far down the shadow sits, in points.
    public let offsetY: CGFloat
    /// The CSS blur radius, in points. SwiftUI's blur radius is half of it.
    public let blur: CGFloat
    /// The CSS spread, in points. Negative, which pulls the shadow in from the sides.
    public let spread: CGFloat

    public init(color: ColorToken, offsetY: CGFloat, blur: CGFloat, spread: CGFloat) {
        self.color = color
        self.offsetY = offsetY
        self.blur = blur
        self.spread = spread
    }

    /// Chips, plates, soft rows and ghost buttons (`--soft-drop: 0 10px 16px -12px`).
    public static let drop = SoftShadow(color: .shadow, offsetY: 10, blur: 16, spread: -12)
    /// Buttons and large rows (`--soft-drop-lg: 0 16px 22px -16px`).
    public static let dropLarge = SoftShadow(color: .shadowLarge, offsetY: 16, blur: 22, spread: -16)

    /// How far below the shape's top edge the blurred shadow begins, in points. Positive means
    /// the shadow never shows above the shape, only below it.
    public var topClearance: CGFloat { offsetY - spread - blur }
}

extension View {
    /// Adds a soft shadow below `shape`, which should match the view's own shape.
    /// Pass `isVisible: false` to drop it, for example on a pressed or disabled control.
    public func softShadow<S: Shape>(_ shadow: SoftShadow = .drop, in shape: S, isVisible: Bool = true) -> some View {
        modifier(SoftShadowModifier(shadow: shadow, shape: shape, isVisible: isVisible))
    }
}

private struct SoftShadowModifier<S: Shape>: ViewModifier {
    let shadow: SoftShadow
    let shape: S
    let isVisible: Bool

    func body(content: Content) -> some View {
        content.background {
            if isVisible {
                shadowLayer
            }
        }
    }

    private var shadowLayer: some View {
        shape
            .fill(Color(token: shadow.color))
            .padding(-shadow.spread)
            .offset(y: shadow.offsetY)
            .blur(radius: shadow.blur / 2)
            .mask {
                // Everything except the shape: a large rectangle with the shape punched out.
                ZStack {
                    Rectangle().padding(-(shadow.offsetY + shadow.blur * 2))
                    shape.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
