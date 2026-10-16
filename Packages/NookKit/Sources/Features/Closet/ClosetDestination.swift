import Models

/// A screen Closet pushes: garment detail and Recently deleted (Phase 7a), Add a piece and Edit
/// (Phase 7b), Suitcases and Laundry (Phase 13) and Profile (Phase 14a). Saved Looks pushes the
/// same screens from a look's piece. `ClosetDestinationScreen` draws them for both tabs.
nonisolated enum ClosetDestination: Hashable, Sendable {
    /// Garment detail (Phase 7a). Carries the name so the title shows before the piece loads.
    case garment(Garment.ID, name: String)
    /// Add a piece (Phase 7b), from a photo or in words, or carrying on with a draft.
    case addPiece(AddPieceStart)
    /// Edit a piece (Phase 7b), from garment detail, or carrying on with a draft from Closet.
    case editPiece(Garment.ID, name: String, resumesDraft: Bool = false)
    /// Suitcases (Phase 13): three favourites, the main closet, and "+ Add a suitcase" (RD-09).
    case suitcases
    /// Every suitcase, with search and the archived ones under their filter (RD-09.3).
    case allSuitcases
    /// One suitcase (Phase 13), from Suitcases or a name on garment detail (LR-11.4).
    /// `startsPacking` opens it on the packing sheet, as after "+ Add a suitcase".
    case suitcase(Suitcase.ID, name: String, startsPacking: Bool = false)
    /// Laundry (Phase 13), only while tracking is on (RD-11).
    case laundry
    /// Recently deleted (LR-16).
    case recentlyDeleted
    /// Style Me with a starting piece, from Style with this (Phase 10a).
    case styleMe(startingWith: Garment.ID, name: String)
    /// Style Me from a source, from a suitcase's "Style me from this suitcase" (Phase 13).
    case styleMeFrom(WardrobeSource)
    /// Make your own look starting from a piece, from Style with this (LR-08.3, Phase 11).
    case makeYourOwnLook(startingWith: Garment.ID, name: String)
    case profile

    nonisolated enum AddPieceStart: Hashable, Sendable {
        /// "How would you like to add it?"
        case photo
        /// Straight to Describe in words.
        case words
        /// Resume on Closet's "Continue where you left off?".
        case resume
    }

    var title: String {
        switch self {
        case .garment(_, let name): name
        case .addPiece: String(localized: "Add a piece", bundle: .module, comment: "Screen title")
        case .editPiece: String(localized: "Edit piece", bundle: .module, comment: "Screen title")
        case .suitcases: String(localized: "Suitcases", bundle: .module, comment: "Screen title")
        case .allSuitcases: SuitcasesText.allTitle
        case .suitcase(_, let name, _): name
        case .laundry: String(localized: "Laundry", bundle: .module, comment: "Screen title")
        case .recentlyDeleted: String(localized: "Recently deleted", bundle: .module, comment: "Screen title")
        case .styleMe, .styleMeFrom: String(localized: "Style Me", bundle: .module, comment: "Screen title")
        case .makeYourOwnLook: String(localized: "Make your own look", bundle: .module, comment: "Screen title")
        case .profile: String(localized: "Profile", bundle: .module, comment: "Screen title")
        }
    }
}
