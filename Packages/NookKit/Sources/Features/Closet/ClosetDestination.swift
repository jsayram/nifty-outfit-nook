import Models

/// A screen Closet pushes. Each is a stand-in until its phase builds it.
nonisolated enum ClosetDestination: Hashable, Sendable {
    /// Garment detail (Phase 7a). Carries the name so the stand-in can show it.
    case garment(Garment.ID, name: String)
    /// Add a piece (Phase 7b), from a photo or in words.
    case addPiece(AddPieceStart)
    /// Suitcases (Phase 13).
    case suitcases
    /// Laundry (Phase 13), only while tracking is on (RD-11).
    case laundry
    /// Recently deleted (LR-16, Phase 7a builds removing a piece).
    case recentlyDeleted
    case profile

    nonisolated enum AddPieceStart: Hashable, Sendable {
        case photo
        case words
    }

    var title: String {
        switch self {
        case .garment(_, let name): name
        case .addPiece: String(localized: "Add a piece", bundle: .module, comment: "Screen title")
        case .suitcases: String(localized: "Suitcases", bundle: .module, comment: "Screen title")
        case .laundry: String(localized: "Laundry", bundle: .module, comment: "Screen title")
        case .recentlyDeleted: String(localized: "Recently deleted", bundle: .module, comment: "Screen title")
        case .profile: String(localized: "Profile", bundle: .module, comment: "Screen title")
        }
    }

    var systemImage: String {
        switch self {
        case .garment: "hanger"
        case .addPiece(.photo): "camera"
        case .addPiece(.words): "pencil"
        case .suitcases: "suitcase.rolling"
        case .laundry: "basket"
        case .recentlyDeleted: "trash"
        case .profile: "person.crop.circle"
        }
    }

    /// A stable name for UI tests.
    var identifier: String {
        switch self {
        case .garment: "garment"
        case .addPiece: "addPiece"
        case .suitcases: "suitcases"
        case .laundry: "laundry"
        case .recentlyDeleted: "recentlyDeleted"
        case .profile: "profile"
        }
    }
}
