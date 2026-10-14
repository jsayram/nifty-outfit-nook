import Foundation

/// A piece she started adding or editing and hasn't saved yet (PRD §7.3, FR-31; Phase 7b).
///
/// The form writes one of these as she goes, so if the app is closed mid-way she's offered
/// "Continue where you left off?" next time. It's kept apart from the garment itself: a draft
/// never changes her closet until she taps Save.
///
/// Data tier: **Sensitive**, because it can hold her notes and her own words for the piece
/// (DATA_MAP.md: a copy takes the tier of what it copies).
public struct GarmentDraft: Identifiable, Hashable, Sendable, Codable {
    /// What the draft will change when she saves it.
    public enum Target: Hashable, Sendable, Codable {
        /// Add a piece.
        case newPiece
        /// Edit this piece.
        case garment(Garment.ID)
    }

    /// Where she was in Add a piece, so Resume opens the same step.
    public enum Step: String, CaseIterable, Hashable, Sendable, Codable {
        /// Choosing how to add it: a photo or words.
        case choose
        /// Describing it in words.
        case words
        /// The details form.
        case details
    }

    public var target: Target
    public var id: Target { target }
    public var step: Step
    /// What the form holds now.
    public var details: GarmentDetails
    /// What the form started from: blank for a new piece, the piece as it was for an edit. The
    /// draft only counts as changed work while `details` differ from it, or she typed words.
    public var base: GarmentDetails
    /// Her own words for the piece (Describe in words). **Sensitive** tier.
    public var description: String
    /// The last time the draft was written.
    public var savedAt: Date

    public init(
        target: Target,
        step: Step,
        details: GarmentDetails,
        base: GarmentDetails,
        description: String = "",
        savedAt: Date
    ) {
        self.target = target
        self.step = step
        self.details = details
        self.base = base
        self.description = description
        self.savedAt = savedAt
    }

    /// True when there's anything to come back to: changed details, or words she typed.
    public var hasChanges: Bool {
        details != base || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
