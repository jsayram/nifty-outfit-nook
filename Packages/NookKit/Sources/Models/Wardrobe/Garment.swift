import Foundation

/// One piece of clothing, a bag or an accessory.
///
/// Data tier: **Personal** (closet details), except `notes`, which is **Sensitive** because she
/// can type anything there (DATA_MAP.md, "Her closet and how she uses it").
///
/// Ownership, laundry, availability, archive and deletion are separate fields, because each one
/// changes for a different reason and none of them implies another (PRD §12).
public struct Garment: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<Garment>

    public let id: ID
    /// Her own name for it, such as "Cute pink shirt".
    public var name: String
    public var category: GarmentCategory
    /// Colour families, main colour first. Empty means the colour is unknown.
    public var colors: [ColorName]
    /// Her words for the exact shade, if she gave any ("mid-wash denim").
    public var colorNote: String?
    /// How it's cut. `nil` means unknown.
    public var fit: GarmentFit?
    public var dressiness: Dressiness
    public var warmth: Warmth
    /// Seasons she wears it in. Empty means unknown, which matches no season.
    public var seasons: Set<Season>
    /// Occasions it suits. Empty means unknown, which matches no occasion.
    public var occasions: Set<Occasion>
    public var brand: String?
    /// The size printed on the label, as written.
    public var sizeLabel: String?
    /// Free-text notes. **Sensitive** tier: never logged, never sent without a consented request.
    public var notes: String
    public var photo: PhotoReference
    /// The piece lifted out of `photo`, with how clean the lift looks (Phase 8b). `nil` until a
    /// cutout has been made, and whenever the photo changes. **Personal** tier, like the photo.
    public var cutout: GarmentCutout?
    public var ownership: Ownership
    /// Only matters when laundry tracking is on (RD-11). Kept when tracking is turned off.
    public var laundry: LaundryState
    public var availability: Availability
    /// Archived pieces stay in the data but leave Closet and styling. No Stage A screen (LR-16).
    public var isArchived: Bool
    /// Set when she chose "Delete it". The piece sits in Recently deleted until `purgeDate`.
    public var deletedAt: Date?
    /// Days she marked it worn (Wear today, LR-10), oldest first, at most one per day.
    public var wornOn: [Date]
    public var addedAt: Date

    public init(
        id: ID,
        name: String,
        category: GarmentCategory,
        colors: [ColorName] = [],
        colorNote: String? = nil,
        fit: GarmentFit? = nil,
        dressiness: Dressiness = .smart,
        warmth: Warmth = .medium,
        seasons: Set<Season> = Set(Season.allCases),
        occasions: Set<Occasion> = [],
        brand: String? = nil,
        sizeLabel: String? = nil,
        notes: String = "",
        photo: PhotoReference = .noPhoto,
        cutout: GarmentCutout? = nil,
        ownership: Ownership = .owned,
        laundry: LaundryState = .clean,
        availability: Availability = .available,
        isArchived: Bool = false,
        deletedAt: Date? = nil,
        wornOn: [Date] = [],
        addedAt: Date
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.colors = colors
        self.colorNote = colorNote
        self.fit = fit
        self.dressiness = dressiness
        self.warmth = warmth
        self.seasons = seasons
        self.occasions = occasions
        self.brand = brand
        self.sizeLabel = sizeLabel
        self.notes = notes
        self.photo = photo
        self.cutout = cutout
        self.ownership = ownership
        self.laundry = laundry
        self.availability = availability
        self.isArchived = isArchived
        self.deletedAt = deletedAt
        self.wornOn = wornOn
        self.addedAt = addedAt
    }

    /// The most recent day she wore it, shown as "Last worn 3 Oct" (LR-10).
    public var lastWorn: Date? { wornOn.max() }

    /// The main colour, if known.
    public var mainColor: ColorName? { colors.first }

    /// True while the piece is in Recently deleted.
    public var isDeleted: Bool { deletedAt != nil }

    /// When a deleted piece is removed for good: 30 days after deletion (PRD §7.4).
    public var purgeDate: Date? {
        deletedAt.map { $0.addingTimeInterval(Self.recentlyDeletedDays * 86_400) }
    }

    /// How long Recently deleted keeps a piece.
    public static let recentlyDeletedDays: Double = 30

    /// True when the piece belongs in Closet: hers (bought counts, even before it arrives),
    /// not archived and not deleted. Wishlist and no-longer-owned pieces are elsewhere.
    public var isInCloset: Bool {
        ownership.isHers && !isArchived && !isDeleted
    }
}

/// Whether a garment is hers. Only `owned` and arrived `purchased` pieces can be styled.
public enum Ownership: Hashable, Sendable, Codable {
    /// Hers. The usual state for anything added to Closet.
    case owned
    /// She said she bought it. It can be styled once it has arrived.
    case purchased(ArrivalState)
    /// A piece she's thinking of buying (LR-12). Never counts as owned.
    case wishlisted
    /// "I don't have it any more" (LR-16). Kept for history, out of Closet and styling.
    case noLongerOwned

    /// Owned, or bought (arrived or not).
    public var isHers: Bool {
        switch self {
        case .owned, .purchased: true
        case .wishlisted, .noLongerOwned: false
        }
    }
}

/// Delivery state of a bought piece.
public enum ArrivalState: String, CaseIterable, Hashable, Sendable, Codable {
    case notArrived
    case arrived
    /// Unknown counts as not arrived for styling.
    case unknown
}

/// Laundry state, only used when Track laundry is on (RD-11).
public enum LaundryState: String, CaseIterable, Hashable, Sendable, Codable {
    case clean
    case dirty
}

/// Whether she can wear it right now, apart from laundry.
public enum Availability: Hashable, Sendable, Codable {
    case available
    /// Lent out, at the tailor and so on. With a date, it's back on that day.
    case unavailable(until: Date?)
}

/// Where a picture comes from: none, the sample art, or a real photo she added (Phase 22a).
public enum PhotoReference: Hashable, Sendable, Codable {
    /// Added by text only. Screens show a plain tile.
    case noPhoto
    /// Bundled sample art, named. Fixtures only.
    case sample(String)
    /// A photo in the app's photo files on the iPhone, saved without its metadata (Phase 22a,
    /// `PhotoFileStore` in Services). The ID is the file's name.
    case stored(EntityID<PhotoReference>)
}
