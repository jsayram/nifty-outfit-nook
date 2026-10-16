import Foundation

/// The hamper on Home (RD-11).
public enum HamperState: Hashable, Sendable {
    /// Tracking is off: a faded, empty hamper with "Laundry · Off".
    case off
    /// Tracking is on and nothing is dirty: "Laundry · all clean".
    case allClean
    /// Tracking is on with dirty pieces: "Laundry · 2 to wash".
    case toWash(Int)

    /// The hamper for the pieces in her closet. Dirty marks are kept while tracking is off,
    /// but the hamper ignores them until she turns it back on (RD-11).
    public init(garments: [Garment], tracksLaundry: Bool) {
        guard tracksLaundry else {
            self = .off
            return
        }
        let dirty = garments.count(where: { $0.isInCloset && $0.laundry == .dirty })
        self = dirty == 0 ? .allClean : .toWash(dirty)
    }
}

/// What the Laundry screen lists and what Mark clean may change (RD-11, PRD §7.3, FR-65).
///
/// Only pieces in her closet count: owned or arrived, not archived, not in Recently deleted.
/// Shared pieces have one status, so a shirt in two suitcases is one dirty piece everywhere.
public struct LaundryBasket: Hashable, Sendable {
    /// Pieces in her closet marked as in the wash, in the order given.
    public let dirty: [Garment]

    public init(garments: [Garment]) {
        dirty = garments.filter { $0.isInCloset && $0.laundry == .dirty }
    }

    /// The dirty pieces packed in this suitcase ("This suitcase", PRD §7.3).
    public func dirty(in suitcase: Suitcase) -> [Garment] {
        dirty.filter { suitcase.contains($0.id) }
    }

    /// The pieces Mark clean may change now: still in her closet and still dirty. Anything else
    /// is skipped, never forced (FR-65).
    public static func cleanable(_ ids: [Garment.ID], in garments: [Garment]) -> [Garment.ID] {
        changeable(ids, in: garments, from: .dirty)
    }

    /// The pieces Undo may put back in the wash: still in her closet and still clean, so Undo
    /// never overwrites a change made since (PRD §7.3).
    public static func undoable(_ ids: [Garment.ID], in garments: [Garment]) -> [Garment.ID] {
        changeable(ids, in: garments, from: .clean)
    }

    private static func changeable(_ ids: [Garment.ID], in garments: [Garment], from state: LaundryState)
        -> [Garment.ID]
    {
        let byID = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<Garment.ID> = []
        return ids.filter { id in
            guard seen.insert(id).inserted, let garment = byID[id] else { return false }
            return garment.isInCloset && garment.laundry == state
        }
    }
}
