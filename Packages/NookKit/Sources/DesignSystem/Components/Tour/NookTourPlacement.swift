import CoreGraphics

/// Where a quick tour's card goes, given the control it points at (Phase 16a, PRD §7.8).
///
/// The card never covers the control. It goes on the side with the most room: below or above
/// the control, then beside it (a wide iPad window). When it fits nowhere without covering the
/// control, as at the largest text sizes, it sits at the top or bottom edge with no tail and the
/// screen shows no spotlight. With no control at all (missing, or scrolled out of sight) it sits
/// in the middle, again without a spotlight.
nonisolated public struct NookTourPlacement: Hashable, Sendable {
    /// Which side of the card the tail sticks out of, toward the control.
    nonisolated public enum TailEdge: String, Hashable, Sendable {
        case top
        case bottom
        case leading
        case trailing
    }

    /// The card's frame.
    public var card: CGRect
    /// The card's side the tail sticks out of. `nil` when there's no spotlight.
    public var tailEdge: TailEdge?
    /// Where along that side the tail's middle sits: an x for top and bottom, a y for leading
    /// and trailing.
    public var tailPosition: CGFloat?
    /// The spotlight's frame: the control with some room around it, or `nil` when the card
    /// shows on its own.
    public var spotlight: CGRect?

    /// The space between the spotlight and the card, which the tail crosses.
    public static let gap: CGFloat = 16
    /// How far the spotlight reaches past the control on every side.
    public static let spotlightPadding: CGFloat = 8
    /// The tail's middle stays this far from the card's corners.
    public static let tailInset: CGFloat = 30

    /// - Parameters:
    ///   - card: the card's size. Its height may already be cut to fit `area`.
    ///   - target: the control's frame, in the same space as `area`.
    ///   - area: where the card may go: the screen inside its safe area and margins.
    public static func place(card: CGSize, target: CGRect?, in area: CGRect) -> NookTourPlacement {
        let size = CGSize(width: min(card.width, area.width), height: min(card.height, area.height))
        guard let target, !target.isNull, !target.isEmpty else {
            return NookTourPlacement(
                card: CGRect(
                    x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width,
                    height: size.height))
        }
        let spot = target.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)

        // Room on each side of the spotlight, less the gap the tail crosses.
        let below = area.maxY - spot.maxY - gap
        let above = spot.minY - area.minY - gap
        let after = area.maxX - spot.maxX - gap
        let before = spot.minX - area.minX - gap

        var options: [(TailEdge, CGFloat)] = []
        if below >= size.height { options.append((.top, below)) }
        if above >= size.height { options.append((.bottom, above)) }
        // Beside only when neither above nor below fits, as on a wide iPad with a tall control.
        if options.isEmpty {
            if after >= size.width { options.append((.leading, after)) }
            if before >= size.width { options.append((.trailing, before)) }
        }

        guard let best = options.max(by: { $0.1 < $1.1 })?.0 else {
            // Nowhere without covering the control: the card goes to the roomier end, alone.
            let y = below >= above ? area.maxY - size.height : area.minY
            let x = clamp(spot.midX - size.width / 2, area.minX, area.maxX - size.width)
            return NookTourPlacement(card: CGRect(origin: CGPoint(x: x, y: y), size: size))
        }

        var placement = NookTourPlacement(card: .zero, tailEdge: best, spotlight: spot)
        switch best {
        case .top, .bottom:
            let x = clamp(spot.midX - size.width / 2, area.minX, area.maxX - size.width)
            let y = best == .top ? spot.maxY + gap : spot.minY - gap - size.height
            placement.card = CGRect(x: x, y: y, width: size.width, height: size.height)
            placement.tailPosition = tailPoint(spot.midX, from: x, length: size.width)
        case .leading, .trailing:
            let x = best == .leading ? spot.maxX + gap : spot.minX - gap - size.width
            let y = clamp(spot.midY - size.height / 2, area.minY, area.maxY - size.height)
            placement.card = CGRect(x: x, y: y, width: size.width, height: size.height)
            placement.tailPosition = tailPoint(spot.midY, from: y, length: size.height)
        }
        return placement
    }

    public init(
        card: CGRect, tailEdge: TailEdge? = nil, tailPosition: CGFloat? = nil, spotlight: CGRect? = nil
    ) {
        self.card = card
        self.tailEdge = tailEdge
        self.tailPosition = tailPosition
        self.spotlight = spotlight
    }

    /// Aims the tail at `aim`, kept clear of the card's corners. A card shorter or narrower than
    /// two insets gets its tail in the middle.
    private static func tailPoint(_ aim: CGFloat, from start: CGFloat, length: CGFloat) -> CGFloat {
        guard length > tailInset * 2 else { return start + length / 2 }
        return clamp(aim, start + tailInset, start + length - tailInset)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, max(low, high)))
    }
}
