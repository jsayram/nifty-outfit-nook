import Foundation
import Models
import Observation

/// Recently deleted (LR-16, PRD §7.4): pieces she chose Delete it for, each kept for 30 days,
/// with Restore, and since Phase 21a Delete now, which deletes one for good after showing what
/// goes with it (`PermanentDeletion`).
///
/// Loading first removes any piece whose 30 days are up (`purgeExpired`), as the PRD asks when
/// the app next runs, so the list never shows a piece past its deadline.
@Observable
final class RecentlyDeletedModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var phase: Phase = .loading
    /// Deleted pieces, most recently deleted first.
    private(set) var pieces: [Garment] = []
    /// When it loaded, for the deadlines.
    private(set) var loadedAt: Date = .now
    /// The piece being restored, so its button shows the dots and a second tap does nothing.
    private(set) var restoring: Garment.ID?
    /// The piece whose Delete now is being prepared or done, so its button shows the dots.
    private(set) var deleting: Garment.ID?
    /// What Delete now would take, while she's asked to confirm.
    var confirming: PermanentDeletionPreview?
    @ObservationIgnored private var loads = LoadGeneration()

    func load(from services: NookServices, now: Date = .now) async {
        let load = loads.begin()
        if pieces.isEmpty { phase = .loading }
        do {
            _ = try await services.closet.purgeExpired(asOf: now)
            let garments = try await services.closet.garments()
            guard loads.isCurrent(load) else { return }
            show(garments, now: now)
        } catch {
            guard loads.isCurrent(load) else { return }
            phase = .failed
        }
    }

    /// Sets the list from loaded garments. Separate from `load` so tests can hand data straight in.
    func show(_ garments: [Garment], now: Date) {
        loadedAt = now
        pieces = garments.filter(\.isDeleted).sorted { lhs, rhs in
            let left = lhs.deletedAt ?? .distantPast
            let right = rhs.deletedAt ?? .distantPast
            return left != right ? left > right : lhs.id < rhs.id
        }
        phase = .loaded
    }

    /// Restore: back in her closet, the same piece with its links (LR-16.3).
    @discardableResult
    func restore(_ id: Garment.ID, in closet: any ClosetStore) async throws(StoreError) -> Garment? {
        guard restoring == nil, deleting == nil, let piece = pieces.first(where: { $0.id == id }) else { return nil }
        restoring = id
        defer { restoring = nil }
        try await closet.restore(id)
        pieces.removeAll { $0.id == id }
        var restored = piece
        restored.deletedAt = nil
        return restored
    }

    /// Delete now: works out what goes with the piece and asks her to confirm.
    func askToDeletePermanently(_ id: Garment.ID, in services: NookServices) async throws(StoreError) {
        guard restoring == nil, deleting == nil, let piece = pieces.first(where: { $0.id == id }) else { return }
        deleting = id
        defer { deleting = nil }
        confirming = try await PermanentDeletion.preview(of: piece, in: services)
    }

    /// She confirmed: the piece is deleted for good and leaves the list. Returns its name.
    @discardableResult
    func deletePermanently(_ preview: PermanentDeletionPreview, in services: NookServices) async throws(StoreError)
        -> String?
    {
        let id = preview.piece.id
        guard restoring == nil, deleting == nil, pieces.contains(where: { $0.id == id }) else { return nil }
        confirming = nil
        deleting = id
        defer { deleting = nil }
        try await PermanentDeletion.delete(id, in: services)
        pieces.removeAll { $0.id == id }
        return preview.piece.name
    }

    var isEmpty: Bool { phase == .loaded && pieces.isEmpty }
}
