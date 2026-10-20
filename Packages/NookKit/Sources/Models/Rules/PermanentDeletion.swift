import Foundation

// "Delete permanently now" in Recently deleted (PRD §7.4, Phase 21a).
//
// She sees what goes before she confirms: the piece with its photo and details, and an unsaved
// Edit of it. Saved looks that use it keep the rest of the look and say a piece was deleted for
// good, as they do after the 30-day purge. Suitcases skip it. Try-on pictures stay until she
// deletes them (PRD §7.5, §9.2.4, as everywhere in Stage A); the PRD's purge of generated images
// that show the piece is a decision for Jose. Deletion markers for sync come with Phase 21b.

/// What deleting a piece for good takes with it, worked out before she confirms.
public struct PermanentDeletionPreview: Hashable, Sendable {
    public var piece: Garment
    /// Saved looks that use it, newest first. They keep their other pieces.
    public var savedLooks: [Look]
    /// Suitcases it's packed in. It no longer shows in them.
    public var suitcases: [Suitcase]
    /// She started an Edit of it and didn't save it. The draft goes too.
    public var hasUnsavedEdit: Bool
    /// Try-on pictures with it in. They stay.
    public var pictureCount: Int

    public init(
        piece: Garment, savedLooks: [Look] = [], suitcases: [Suitcase] = [], hasUnsavedEdit: Bool = false,
        pictureCount: Int = 0
    ) {
        self.piece = piece
        self.savedLooks = savedLooks
        self.suitcases = suitcases
        self.hasUnsavedEdit = hasUnsavedEdit
        self.pictureCount = pictureCount
    }

    /// Whether it has a photo of her own piece (not a drawing) that goes with it.
    public var hasPhoto: Bool { piece.photo != .noPhoto }
}

/// Deleting a piece from Recently deleted for good.
public enum PermanentDeletion {
    /// What goes with `piece`, from what the stores hold now.
    public static func preview(
        of piece: Garment, looks: [Look], suitcases: [Suitcase], drafts: [GarmentDraft], pictures: [TryOnPicture]
    ) -> PermanentDeletionPreview {
        PermanentDeletionPreview(
            piece: piece,
            savedLooks: looks.filter { $0.isSaved && $0.garmentIDs.contains(piece.id) }
                .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id < $1.id },
            suitcases: suitcases.filter { $0.garmentIDs.contains(piece.id) }.sorted { $0.name < $1.name },
            hasUnsavedEdit: drafts.contains { $0.target == .garment(piece.id) },
            pictureCount: pictures.count { picture in
                picture.captured.pieces.contains { $0.garmentID == piece.id }
            })
    }

    /// The preview for a piece in Recently deleted, read from the services' stores.
    public static func preview(of piece: Garment, in services: NookServices) async throws(StoreError)
        -> PermanentDeletionPreview
    {
        preview(
            of: piece, looks: try await services.looks.looks(), suitcases: try await services.suitcases.suitcases(),
            drafts: try await services.drafts.drafts(), pictures: try await services.pictures.pictures())
    }

    /// Deletes the piece for good: its unsaved Edit first, then the piece itself, so a failure
    /// part way leaves the piece in Recently deleted, where she can try again. Only a piece in
    /// Recently deleted can go (`ClosetStore.deletePermanently`).
    public static func delete(_ id: Garment.ID, in services: NookServices) async throws(StoreError) {
        guard try await services.closet.garment(id).isDeleted else { throw .notFound }
        try await services.drafts.discard(.garment(id))
        try await services.closet.deletePermanently(id)
    }
}
