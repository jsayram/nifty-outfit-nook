import Foundation

/// A named group of garments kept somewhere else, such as "Jose's house" (PRD §7.7).
///
/// Data tier: **Personal**. A suitcase name can reveal where she'll be, so it isn't sent with a
/// styling request unless she includes it (DATA_MAP.md).
///
/// A suitcase links to garments by ID and never copies them. A garment can be in several.
public struct Suitcase: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<Suitcase>

    public let id: ID
    public var name: String
    /// Which drawing stands for it in the hall.
    public var icon: SuitcaseIcon
    /// Member garments. A set, so a piece can't be added twice.
    public var garmentIDs: Set<Garment.ID>
    /// When it was last used as the Style Me source. Favourites are the three most recent (RD-09).
    public var lastUsedAt: Date?
    public var isArchived: Bool
    public var createdAt: Date

    public init(
        id: ID,
        name: String,
        icon: SuitcaseIcon = .rolling,
        garmentIDs: Set<Garment.ID> = [],
        lastUsedAt: Date? = nil,
        isArchived: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.garmentIDs = garmentIDs
        self.lastUsedAt = lastUsedAt
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    public func contains(_ garmentID: Garment.ID) -> Bool {
        garmentIDs.contains(garmentID)
    }
}

/// The drawing used for a suitcase in the hall scene and on its plate.
public enum SuitcaseIcon: String, CaseIterable, Hashable, Sendable, Codable {
    case rolling
    case duffel
    case weekender
    case backpack
    case tote
}

/// Where Style Me and Closet take clothes from: the whole closet or one suitcase.
public enum WardrobeSource: Hashable, Sendable, Codable {
    case mainCloset
    case suitcase(Suitcase.ID)

    public var suitcaseID: Suitcase.ID? {
        switch self {
        case .mainCloset: nil
        case .suitcase(let id): id
        }
    }

    /// A suitcase source always styles from owned pieces only (PRD §7.7, §8.1, LR-05b).
    public var isSuitcase: Bool { suitcaseID != nil }
}
