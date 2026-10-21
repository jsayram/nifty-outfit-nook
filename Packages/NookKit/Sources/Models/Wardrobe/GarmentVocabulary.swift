import Foundation

// The fixed words used to describe a garment. These are stored facts she confirms or edits.
// Display text for each case lives with the screens (Features), not here, so Models carries no
// user-facing strings.

/// The kind of piece. Matches the piece chips in Closet and Saved Looks (LR-09).
public enum GarmentCategory: String, CaseIterable, Codable, Sendable, Comparable {
    case top
    case bottom
    case dress
    case layer
    case shoes
    case bag
    case accessory

    /// Body order, top to bottom, used to list a look's pieces.
    public var listOrder: Int {
        switch self {
        case .layer: 0
        case .top: 1
        case .dress: 2
        case .bottom: 3
        case .shoes: 4
        case .bag: 5
        case .accessory: 6
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.listOrder < rhs.listOrder
    }
}

/// A named colour family, used for the colour swatches (LR-09) and colour wishes.
/// Her own words for a shade ("mid-wash denim") go in `Garment.colorNote`.
public enum ColorName: String, CaseIterable, Codable, Sendable {
    case black
    case white
    case cream
    case beige
    case tan
    case brown
    case gray
    case navy
    case blue
    case denim
    case green
    case olive
    case red
    case brick
    case burgundy
    case pink
    case purple
    case yellow
    case orange
    case multicolor
}

/// How dressy a piece is. "Dressed up" swaps in a dressier piece she owns (LR-05a).
public enum Dressiness: Int, CaseIterable, Codable, Sendable, Comparable {
    case casual = 0
    case smart = 1
    case dressy = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How a piece is cut. Matched against today's comfort or her usual fit (see `Comfort`).
public enum GarmentFit: String, CaseIterable, Codable, Sendable {
    case fitted
    case regular
    case relaxed
}

/// How warm a piece is to wear.
public enum Warmth: Int, CaseIterable, Codable, Sendable, Comparable {
    case light = 0
    case medium = 1
    case warm = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A season. A garment lists the seasons she wears it in.
public enum Season: String, CaseIterable, Codable, Sendable {
    case spring
    case summer
    case fall
    case winter

    /// The season for a date, by month in the northern hemisphere (March to May is spring).
    /// Her location isn't stored, so this is a plain calendar fact.
    public static func of(_ date: Date, calendar: Calendar) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .fall
        default: .winter
        }
    }
}

/// Where she's going. A garment lists the occasions it suits; a request names one.
public enum Occasion: String, CaseIterable, Codable, Sendable {
    case office
    case casual
    case brunch
    case dateNight
    case event
    case concert
    case other
}

/// A narrower kind within a `GarmentCategory`, such as Cardigan or Blazer within Layers (PRD §7.6,
/// the Add a piece mockup). Optional on every piece: `nil` means she didn't pick one, or none of
/// these fits. Raw values are stored, so never rename or reuse one.
public enum GarmentSubKind: String, CaseIterable, Codable, Sendable {
    // Tops
    case blouse
    case tee
    case shirt
    case sweater
    case knitTop
    case tank
    // Layers
    case cardigan
    case jacket
    case blazer
    case coat
    case vest
    // Bottoms
    case trousers
    case jeans
    case skirt
    case shorts
    case leggings
    // Shoes
    case flats
    case heels
    case sneakers
    case loafers
    case boots
    case sandals
    // Bags
    case handbag
    case tote
    case crossbody
    case clutch
    case backpack
    // Accessories
    case scarf
    case belt
    case hat
    case jewelry

    /// The kind this one belongs to.
    public var category: GarmentCategory {
        switch self {
        case .blouse, .tee, .shirt, .sweater, .knitTop, .tank: .top
        case .cardigan, .jacket, .blazer, .coat, .vest: .layer
        case .trousers, .jeans, .skirt, .shorts, .leggings: .bottom
        case .flats, .heels, .sneakers, .loafers, .boots, .sandals: .shoes
        case .handbag, .tote, .crossbody, .clutch, .backpack: .bag
        case .scarf, .belt, .hat, .jewelry: .accessory
        }
    }

    /// The choices for one kind, in the order the form shows them. Dresses have none yet.
    public static func choices(for category: GarmentCategory) -> [GarmentSubKind] {
        allCases.filter { $0.category == category }
    }
}
