import Foundation

/// A look she started in Make your own look and hasn't saved yet (LR-08.4, PRD §7.3).
///
/// The editor writes one on every change, so if the app is closed mid-way she's offered to
/// carry on next time. It's kept apart from her saved looks: a draft never changes Saved Looks
/// until she taps Save look. There's one at a time.
///
/// Data tier: **Personal**, like a saved look (DATA_MAP.md, "Saved looks").
public struct LookDraft: Hashable, Sendable, Codable {
    /// The name she typed so far. Empty until she types one.
    public var name: String
    /// Where the pieces come from. Make your own look uses the main closet in Stage A.
    public var source: WardrobeSource
    /// Her pieces so far, in the order she added them.
    public var garmentIDs: [Garment.ID]
    /// The piece Style with this started from, if any.
    public var startingPieceID: Garment.ID?
    /// The last time the draft was written.
    public var savedAt: Date

    public init(
        name: String = "",
        source: WardrobeSource = .mainCloset,
        garmentIDs: [Garment.ID] = [],
        startingPieceID: Garment.ID? = nil,
        savedAt: Date
    ) {
        self.name = name
        self.source = source
        self.garmentIDs = garmentIDs
        self.startingPieceID = startingPieceID
        self.savedAt = savedAt
    }

    /// True when there's anything to come back to: pieces beyond the one it started with, or a
    /// name she typed.
    public var hasChanges: Bool {
        let started = startingPieceID.map { [$0] } ?? []
        return garmentIDs != started || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Where the unsaved Make your own look draft is kept (LR-08.4).
///
/// Stage A keeps it in memory, like every other store, so it lasts until the app is closed. UI
/// tests seed one at launch with `-fixtures demo:draft=look`. Phase 21a puts durable storage
/// behind this protocol.
public protocol LookDraftStore: ErasableStore {
    func draft() async throws(StoreError) -> LookDraft?
    /// Replaces the draft.
    func save(_ draft: LookDraft) async throws(StoreError)
    /// Removes the draft. Removing when there's none is fine.
    func discard() async throws(StoreError)
}
