import Foundation

// "Delete permanently now" in Recently deleted (PRD §7.4, Phase 21a), and the 30-day purge.
//
// She sees what goes before she confirms: the piece with its photo and details, an unsaved Edit of
// it, and the try-on pictures that show it. Saved looks that use it keep the rest of the look and
// say a piece was deleted for good. Suitcases skip it. Since Phase 21b the try-on pictures that
// show a piece go when the piece is deleted for good, as the PRD says (Jose, 20 October 2026), and
// the piece leaves a content-free deletion marker, so a restore never brings either back.

/// What deleting a piece for good takes with it, worked out before she confirms.
public struct PermanentDeletionPreview: Hashable, Sendable {
    public var piece: Garment
    /// Saved looks that use it, newest first. They keep their other pieces.
    public var savedLooks: [Look]
    /// Suitcases it's packed in. It no longer shows in them.
    public var suitcases: [Suitcase]
    /// She started an Edit of it and didn't save it. The draft goes too.
    public var hasUnsavedEdit: Bool
    /// Try-on pictures with it in. They're deleted with it.
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
            pictureCount: showing([piece.id], in: pictures).count)
    }

    /// The try-on pictures that show any of these pieces.
    public static func showing(_ ids: some Collection<Garment.ID>, in pictures: [TryOnPicture]) -> [TryOnPicture] {
        let ids = Set(ids)
        return pictures.filter { picture in picture.captured.pieces.contains { $0.garmentID.map(ids.contains) ?? false }
        }
    }

    /// The preview for a piece in Recently deleted, read from the services' stores.
    public static func preview(of piece: Garment, in services: NookServices) async throws(StoreError)
        -> PermanentDeletionPreview
    {
        preview(
            of: piece, looks: try await services.looks.looks(), suitcases: try await services.suitcases.suitcases(),
            drafts: try await services.drafts.drafts(), pictures: try await services.pictures.pictures())
    }

    /// Deletes the piece for good: its unsaved Edit and the try-on pictures that show it first,
    /// then the piece itself, so a failure part way leaves the piece in Recently deleted, where she
    /// can try again. Only a piece in Recently deleted can go (`ClosetStore.deletePermanently`).
    public static func delete(_ id: Garment.ID, in services: NookServices) async throws(StoreError) {
        let piece = try await services.closet.garment(id)
        guard piece.isDeleted else { throw .notFound }
        let draft = try await services.drafts.draft(for: .garment(id))
        try await services.drafts.discard(.garment(id))
        let pictures = try await deletePictures(showing: [id], in: services)
        try await services.closet.deletePermanently(id)
        // Its photo, cutout and pictures' files go once nothing points to them (Phase 22b).
        await services.imageFiles.release(
            piece.imageReferences + (draft.map(Self.photos) ?? []) + pictures.flatMap(\.storedImages),
            deletedForGood: true)
    }

    /// The 30-day purge: the pictures that show each piece whose time is up go first, then the
    /// pieces (`ClosetStore.purgeExpired`). If the pictures can't be deleted, nothing is purged
    /// and the next try does both.
    @discardableResult
    public static func purgeExpired(asOf date: Date, in services: NookServices) async throws(StoreError)
        -> [Garment.ID]
    {
        let expiring = try await services.closet.garments().filter { $0.purgeDate.map { $0 <= date } ?? false }
        var pictures: [TryOnPicture] = []
        if !expiring.isEmpty {
            pictures = try await deletePictures(showing: expiring.map(\.id), in: services)
        }
        let purged = try await services.closet.purgeExpired(asOf: date)
        let gone = Set(purged)
        let photos = expiring.filter { gone.contains($0.id) }.flatMap(\.imageReferences)
        if !photos.isEmpty || !pictures.isEmpty {
            await services.imageFiles.release(photos + pictures.flatMap(\.storedImages), deletedForGood: true)
        }
        return purged
    }

    /// Deletes the pictures that show any of these pieces, and returns them.
    @discardableResult
    private static func deletePictures(showing ids: [Garment.ID], in services: NookServices) async throws(StoreError)
        -> [TryOnPicture]
    {
        let pictures = showing(ids, in: try await services.pictures.pictures())
        for picture in pictures {
            try await services.pictures.delete(picture.id)
        }
        return pictures
    }

    /// The photos an unsaved Add a piece or Edit points to.
    private static func photos(of draft: GarmentDraft) -> [PhotoReference] {
        [draft.details.photo, draft.base.photo]
    }
}
