import Foundation

/// An outfit: a set of pieces shown as one sticker bundle (RD-07).
///
/// Data tier: **Personal** (DATA_MAP.md, "Saved looks, results, version kind").
///
/// A styling result is one base outfit in three versions (LR-05a). Each version is its own
/// `Look`, linked to the others by `resultID`. A look she built herself has no result and no
/// version. Unsaved results are kept too (background history, LR-06), with `isSaved` false.
public struct Look: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<Look>

    public let id: ID
    /// The styling result this look is a version of. `nil` for a look she made herself.
    public var resultID: StyleResult.ID?
    /// Simple, Dressed up or Something new. `nil` for a look she made herself.
    public var version: LookVersion?
    public var pieces: [LookPiece]
    /// Set when she saves it (LR-08). `nil` until then.
    public var name: String?
    public var occasion: Occasion?
    /// The source the look was made from. Captured, not a promise the pieces are still there.
    public var source: WardrobeSource
    public var isSaved: Bool
    /// When she saved it, for "Saved 3 Oct" and the newest-first order on Saved Looks and the
    /// Home shelf (Phase 12a). `nil` while it isn't saved.
    public var savedAt: Date?
    /// Days she chose Wear today for this look (LR-10), oldest first, at most one per day.
    public var wornOn: [Date]
    /// The simulated try-on picture made for this look, if any (RD-06).
    public var tryOnPictureID: TryOnPicture.ID?
    public var createdAt: Date

    public init(
        id: ID,
        resultID: StyleResult.ID? = nil,
        version: LookVersion? = nil,
        pieces: [LookPiece],
        name: String? = nil,
        occasion: Occasion? = nil,
        source: WardrobeSource = .mainCloset,
        isSaved: Bool = false,
        savedAt: Date? = nil,
        wornOn: [Date] = [],
        tryOnPictureID: TryOnPicture.ID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.resultID = resultID
        self.version = version
        self.pieces = pieces
        self.name = name
        self.occasion = occasion
        self.source = source
        self.isSaved = isSaved
        self.savedAt = savedAt
        self.wornOn = wornOn
        self.tryOnPictureID = tryOnPictureID
        self.createdAt = createdAt
    }

    /// IDs of the owned pieces, in piece order.
    public var garmentIDs: [Garment.ID] {
        pieces.compactMap(\.garmentID)
    }

    /// The pieces she doesn't own ("Not in your closet").
    public var ideas: [PieceIdea] {
        pieces.compactMap(\.idea)
    }

    /// True for a look she built in Make your own look.
    public var isMadeByHer: Bool { version == nil }

    public var lastWorn: Date? { wornOn.max() }

    /// When it went into Saved Looks: `savedAt`, or for a look saved before that was recorded,
    /// when it was made.
    public var savedDate: Date { savedAt ?? createdAt }
}

/// The three versions of one styling result (LR-05a), in the order the switch shows them.
public enum LookVersion: String, CaseIterable, Hashable, Sendable, Codable {
    /// Easy and safe.
    case simple
    /// The same outfit, a little classier: one or two pieces swapped for dressier ones she owns.
    case dressedUp
    /// The same outfit plus one piece she doesn't own, or another owned version with Only mine.
    case somethingNew
}

/// One piece in a look: a garment she owns, or an idea for one she doesn't.
public struct LookPiece: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<LookPiece>

    public let id: ID
    public var content: Content
    /// True when this piece is also in the Simple version ("Same as Simple", LR-05a.3).
    public var isSameAsSimple: Bool

    public init(id: ID, content: Content, isSameAsSimple: Bool = false) {
        self.id = id
        self.content = content
        self.isSameAsSimple = isSameAsSimple
    }

    public enum Content: Hashable, Sendable, Codable {
        /// A garment from her closet.
        case garment(Garment.ID)
        /// A piece she doesn't own. It never becomes owned by being in a look (FR-37).
        case idea(PieceIdea)
    }

    public var garmentID: Garment.ID? {
        if case .garment(let id) = content { id } else { nil }
    }

    public var idea: PieceIdea? {
        if case .idea(let idea) = content { idea } else { nil }
    }

    public var isIdea: Bool { idea != nil }
}

/// A suggested piece she doesn't own, tagged "Not in your closet" with Find one (LR-05b).
public struct PieceIdea: Hashable, Sendable, Codable {
    /// A short description, such as "Cropped cream cardigan".
    public var name: String
    public var category: GarmentCategory
    public var colors: [ColorName]

    public init(name: String, category: GarmentCategory, colors: [ColorName] = []) {
        self.name = name
        self.category = category
        self.colors = colors
    }
}

/// A simulated picture of her wearing a look (RD-06). Always labelled Simulated.
///
/// Data tier: **Sensitive** (a picture of a person). Stage A only has the placeholder; real
/// pictures wait for Phase 33's gates.
public struct TryOnPicture: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<TryOnPicture>

    public let id: ID
    public var lookID: Look.ID
    public var image: PhotoReference
    public var createdAt: Date

    public init(id: ID, lookID: Look.ID, image: PhotoReference, createdAt: Date) {
        self.id = id
        self.lookID = lookID
        self.image = image
        self.createdAt = createdAt
    }
}
