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
