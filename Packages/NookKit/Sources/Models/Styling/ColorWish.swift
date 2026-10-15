import Foundation

/// A colour she'd like in the look, for one request (PRD §8.3, FR-05, FR-48).
///
/// Data tier: **Personal**. Like Comfort, it belongs to one request and the next new request
/// starts with none (RD-02.4).
public struct ColorWish: Hashable, Sendable, Codable {
    public var family: ColorName
    /// Preferred: used when it works. Required: every look has it, or the result says why.
    public var strength: ColorStrength
    /// Where the colour goes.
    public var scope: ColorScope

    public init(_ family: ColorName, strength: ColorStrength = .preferred, scope: ColorScope = .anyPiece) {
        self.family = family
        self.strength = strength
        self.scope = scope
    }

    /// True when this piece could carry the colour where she asked for it. A plain lookup on
    /// stored facts (the piece's kind and colours), not a styling rule.
    public func fits(_ garment: Garment) -> Bool {
        garment.colors.contains(family) && scope.includes(garment.category)
    }
}

/// How strongly a colour wish counts (PRD §8.3).
public enum ColorStrength: String, CaseIterable, Hashable, Sendable, Codable {
    case preferred
    case required
}

/// Where a colour wish applies: one piece of a kind, any one piece, or the look's overall palette.
public enum ColorScope: String, CaseIterable, Hashable, Sendable, Codable {
    case anyPiece
    case top
    case bottom
    case dress
    case layer
    case shoes
    case wholePalette

    /// The kinds of piece that can carry the colour for this scope.
    public var categories: Set<GarmentCategory> {
        switch self {
        case .anyPiece, .wholePalette: Set(GarmentCategory.allCases)
        case .top: [.top]
        case .bottom: [.bottom]
        case .dress: [.dress]
        case .layer: [.layer]
        case .shoes: [.shoes]
        }
    }

    public func includes(_ category: GarmentCategory) -> Bool {
        categories.contains(category)
    }
}
