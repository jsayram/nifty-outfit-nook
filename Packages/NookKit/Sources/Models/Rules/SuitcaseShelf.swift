import Foundation

/// How Suitcases arranges her suitcases (RD-09, LR-17).
///
/// Favourites are the three most recently used, with no star to manage. "See all" appears only
/// when there are more than three. Archived suitcases appear only under an explicit filter.
public struct SuitcaseShelf: Hashable, Sendable {
    /// How many favourites show before See all.
    public static let favoriteCount = 3

    /// Up to three suitcases, most recently used first.
    public let favorites: [Suitcase]
    /// Every suitcase that isn't archived: the favourites first, then the rest in the same order.
    public let all: [Suitcase]
    /// Archived suitcases, for the explicit filter only (RD-09.3).
    public let archived: [Suitcase]

    public init(_ suitcases: [Suitcase]) {
        let ordered = suitcases.sorted(by: Self.isOrderedBefore)
        all = ordered.filter { !$0.isArchived }
        archived = ordered.filter(\.isArchived)
        favorites = Array(all.prefix(Self.favoriteCount))
    }

    /// True when there are more suitcases than favourites ("Your 3 favourites · See all 5").
    public var showsSeeAll: Bool { all.count > Self.favoriteCount }

    /// Most recently used first. Never-used suitcases follow, newest first, then by name and ID
    /// so the order is always the same.
    static func isOrderedBefore(_ lhs: Suitcase, _ rhs: Suitcase) -> Bool {
        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case (let left?, let right?) where left != right: return left > right
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        let byName = lhs.name.localizedStandardCompare(rhs.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.id < rhs.id
    }
}
