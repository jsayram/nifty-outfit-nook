import Foundation

// The services Add a piece uses (Phase 7b): unsaved drafts, the photo step and "Describe in
// words". Stage A fills each with a stand-in from Fixtures. None of them reaches the network.

/// Where unsaved Add a piece and Edit work is kept (PRD §7.3, FR-31).
///
/// One draft per target: a new piece, or one per garment being edited. Saving replaces the
/// draft for its target.
///
/// Stage A keeps drafts in memory only, like every other store, so they last until the app is
/// closed. Phase 21a puts durable storage behind this protocol, with the same file protection
/// as the rest of her closet (`docs/add-a-piece.md` explains why it waits).
public protocol DraftStore: Sendable {
    /// Every draft, most recently saved first.
    func drafts() async throws(StoreError) -> [GarmentDraft]
    func draft(for target: GarmentDraft.Target) async throws(StoreError) -> GarmentDraft?
    /// Adds the draft, or replaces the one for the same target.
    func save(_ draft: GarmentDraft) async throws(StoreError)
    /// Removes the draft for this target. Removing one that isn't there is fine.
    func discard(_ target: GarmentDraft.Target) async throws(StoreError)
}

/// Where a photo comes from on the Add a piece screen.
public enum PhotoSource: String, CaseIterable, Hashable, Sendable {
    case camera
    case library
    /// A photo she copied from somewhere else.
    case paste
}

/// Why the photo step didn't give a photo.
public enum PhotoIntakeError: Error, Hashable, Sendable {
    /// The picture couldn't be read. Nothing was saved.
    case unreadable
    /// She backed out of the camera or picker.
    case cancelled
}

/// The photo step of Add a piece.
///
/// Stage A has a stand-in that hands back a sample picture without asking for any permission.
/// Phase 22a puts the system photo picker and the camera behind this protocol.
public protocol PhotoIntake: Sendable {
    func photo(from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference
}

/// One detail suggested from her description of a piece. She accepts or skips each one, and
/// nothing is filled in until she accepts it.
public enum GarmentSuggestion: Hashable, Sendable {
    case name(String)
    case category(GarmentCategory)
    /// Colour families, main first, with the shade word she used ("Sage").
    case colors([ColorName], note: String?)
    case fit(GarmentFit)
    case dressiness(Dressiness)
    case warmth(Warmth)
    case seasons(Set<Season>)
    case occasions(Set<Occasion>)
    case brand(String)
    /// Something she mentioned that has no field, such as "gold buttons". Goes in her notes.
    case detail(String)

    /// Fills the matching field. A detail is added to her notes on its own line.
    public func apply(to details: inout GarmentDetails) {
        switch self {
        case .name(let name): details.name = name
        case .category(let category): details.category = category
        case .colors(let colors, let note):
            details.colors = colors
            if let note { details.colorNote = note }
        case .fit(let fit): details.fit = fit
        case .dressiness(let dressiness): details.dressiness = dressiness
        case .warmth(let warmth): details.warmth = warmth
        case .seasons(let seasons): details.seasons = seasons
        case .occasions(let occasions): details.occasions = occasions
        case .brand(let brand): details.brand = brand
        case .detail(let detail):
            let notes = details.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !notes.localizedCaseInsensitiveContains(detail) else { return }
            details.notes = notes.isEmpty ? detail : notes + "\n" + detail
        }
    }
}

/// Why no suggestions came back.
public enum DescriptionError: Error, Hashable, Sendable {
    case unavailable
    case cancelled
}

/// Reads her description of a piece ("Sage green cardigan with gold buttons") and suggests
/// details for the form.
///
/// Stage A has a deterministic word matcher on the phone (Fixtures). A real reader, if one is
/// ever added, sits behind this protocol and follows the AI rules in SECURITY_STANDARD.md §7.
public protocol GarmentDescriptionReader: Sendable {
    /// Suggestions in form order. Empty when nothing was recognised.
    func suggestions(for description: String) async throws(DescriptionError) -> [GarmentSuggestion]
}
