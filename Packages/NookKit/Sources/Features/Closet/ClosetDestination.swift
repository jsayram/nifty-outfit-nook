import Models

/// A screen Closet pushes. Garment detail and Recently deleted are built (Phase 7a); the rest are
/// stand-ins until their phases build them.
nonisolated enum ClosetDestination: Hashable, Sendable {
    /// Garment detail (Phase 7a). Carries the name so the title shows before the piece loads.
    case garment(Garment.ID, name: String)
    /// Add a piece (Phase 7b), from a photo or in words.
    case addPiece(AddPieceStart)
    /// Edit a piece (Phase 7b), from garment detail.
    case editPiece(Garment.ID, name: String)
    /// Suitcases (Phase 13).
    case suitcases
    /// One suitcase (Phase 13), from a name on garment detail (LR-11.4).
    case suitcase(Suitcase.ID, name: String)
    /// Laundry (Phase 13), only while tracking is on (RD-11).
    case laundry
    /// Recently deleted (LR-16).
    case recentlyDeleted
    /// Style Me with a starting piece, from Style with this (Phase 10a builds the request).
    case styleMe(startingWith: Garment.ID, name: String)
    /// Make your own look starting from a piece, from Style with this (LR-08.3, Phase 11).
    case makeYourOwnLook(startingWith: Garment.ID, name: String)
    case profile

    nonisolated enum AddPieceStart: Hashable, Sendable {
        case photo
        case words
    }

    var title: String {
        switch self {
        case .garment(_, let name): name
        case .addPiece: String(localized: "Add a piece", bundle: .module, comment: "Screen title")
        case .editPiece: String(localized: "Edit piece", bundle: .module, comment: "Screen title")
        case .suitcases: String(localized: "Suitcases", bundle: .module, comment: "Screen title")
        case .suitcase(_, let name): name
        case .laundry: String(localized: "Laundry", bundle: .module, comment: "Screen title")
        case .recentlyDeleted: String(localized: "Recently deleted", bundle: .module, comment: "Screen title")
        case .styleMe: String(localized: "Style Me", bundle: .module, comment: "Screen title")
        case .makeYourOwnLook: String(localized: "Make your own look", bundle: .module, comment: "Screen title")
        case .profile: String(localized: "Profile", bundle: .module, comment: "Screen title")
        }
    }

    var systemImage: String {
        switch self {
        case .garment: "hanger"
        case .addPiece(.photo): "camera"
        case .addPiece(.words): "pencil"
        case .editPiece: "pencil"
        case .suitcases, .suitcase: "suitcase.rolling"
        case .laundry: "basket"
        case .recentlyDeleted: "trash"
        case .styleMe: "sparkles"
        case .makeYourOwnLook: "square.stack"
        case .profile: "person.crop.circle"
        }
    }

    /// A stable name for UI tests.
    var identifier: String {
        switch self {
        case .garment: "garment"
        case .addPiece: "addPiece"
        case .editPiece: "editPiece"
        case .suitcases: "suitcases"
        case .suitcase: "suitcase"
        case .laundry: "laundry"
        case .recentlyDeleted: "recentlyDeleted"
        case .styleMe: "styleMe"
        case .makeYourOwnLook: "makeYourOwnLook"
        case .profile: "profile"
        }
    }
}
