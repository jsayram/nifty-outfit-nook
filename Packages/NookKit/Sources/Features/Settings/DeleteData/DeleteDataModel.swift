import Foundation
import Models
import Observation

/// Delete my data (Phase 14b, PRD §15.4, SECURITY_STANDARD §9).
///
/// The screen first says what will go, with live counts, then asks once more, then deletes every
/// part through `DataDeletionService` and reports part by part. When everything is gone the app
/// starts fresh (`DataDeletedAction`); when a part couldn't be deleted, the screen says which and
/// offers Try again, which deletes again (deleting is safe to repeat).
@Observable
final class DeleteDataModel {
    enum Phase: Equatable {
        case ready
        case deleting
        /// Something wasn't deleted. A complete deletion doesn't stay here: the app starts fresh.
        case incomplete(DeletionReport)
    }

    /// How much there is, for the list. Read before she decides.
    struct Counts: Hashable {
        var pieces = 0
        var looks = 0
        var pictures = 0
        var suitcases = 0
        var drafts = 0
    }

    private(set) var phase: Phase = .ready
    /// `nil` until read, or when a store couldn't be read: the list then shows without numbers.
    private(set) var counts: Counts?
    /// What the deletion covers, from the service, in reading order (closet first).
    private(set) var parts: [DataPart] = DataPart.allCases
    @ObservationIgnored private var loads = LoadGeneration()
    let scope = DeletionScope.thisDevice

    func load(from services: NookServices) async {
        let covered = services.deletion.parts(in: scope)
        parts = DataPart.allCases.filter(covered.contains)
        let load = loads.begin()
        do {
            var counts = Counts()
            counts.pieces = try await services.closet.garments().count
            counts.looks = try await services.looks.looks().count
            counts.pictures = try await services.pictures.pictures().count
            counts.suitcases = try await services.suitcases.suitcases().count
            counts.drafts = try await services.drafts.drafts().count
            if try await services.lookDrafts.draft() != nil { counts.drafts += 1 }
            if try await services.feedbackDrafts.draft() != nil { counts.drafts += 1 }
            guard loads.isCurrent(load) else { return }
            self.counts = counts
        } catch {
            guard loads.isCurrent(load) else { return }
            counts = nil
        }
    }

    /// Sets the counts directly, for snapshot tests.
    func show(_ counts: Counts?, phase: Phase = .ready) {
        self.counts = counts
        self.phase = phase
    }

    /// Deletes everything in scope. Returns true when every part was deleted.
    func delete(in services: NookServices) async -> Bool {
        guard phase != .deleting else { return false }
        phase = .deleting
        let report = await services.deletion.delete(scope)
        if report.isComplete {
            phase = .ready
            return true
        }
        phase = .incomplete(report)
        return false
    }
}
