import Foundation
import Models
import Observation

/// Recently deleted (LR-16, PRD §7.4): pieces she chose Delete it for, each kept for 30 days,
/// with Restore.
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

    func load(from services: NookServices?, now: Date = .now) async {
        guard let services else {
            phase = .loaded
            return
        }
        if pieces.isEmpty { phase = .loading }
        do {
            _ = try await services.closet.purgeExpired(asOf: now)
            show(try await services.closet.garments(), now: now)
        } catch {
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
        guard restoring == nil, let piece = pieces.first(where: { $0.id == id }) else { return nil }
        restoring = id
        defer { restoring = nil }
        try await closet.restore(id)
        pieces.removeAll { $0.id == id }
        var restored = piece
        restored.deletedAt = nil
        return restored
    }

    var isEmpty: Bool { phase == .loaded && pieces.isEmpty }
}
