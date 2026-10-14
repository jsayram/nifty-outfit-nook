import CoreGraphics
import Models

/// Which hamper drawing the room shows (RD-11).
///
/// - Tracking off: the empty hamper, faded, with the quiet "Laundry · Off" plate.
/// - Tracking on and nothing dirty: the empty hamper.
/// - A few pieces to wash: a subtle heap of clothes just above the rim.
/// - `fullFrom` pieces or more: a taller heap with a sleeve over the rim.
nonisolated enum HamperLook: String, CaseIterable, Hashable, Sendable {
    case faded
    case empty
    case some
    case full

    /// From this many pieces to wash, the hamper looks full.
    static let fullFrom = 6

    /// While the closet loads (`nil`), the hamper is plain and empty rather than guessing.
    init(hamper: HamperState?) {
        switch hamper {
        case .off: self = .faded
        case .allClean, nil: self = .empty
        case .toWash(let count): self = count >= Self.fullFrom ? .full : .some
        }
    }

    var art: RoomArt {
        switch self {
        case .faded: .hamperFaded
        case .empty: .hamper
        case .some: .hamperSome
        case .full: .hamperFull
        }
    }

    /// Where the drawing sits. The full hamper is taller, for the heap above the rim; its basket
    /// lands in the same place as the others.
    var stageRect: CGRect {
        self == .full ? RoomStage.hamperFullArt : RoomStage.hamperArt
    }
}
