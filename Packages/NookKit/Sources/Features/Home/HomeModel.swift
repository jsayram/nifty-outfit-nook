import Models
import Observation

/// Loads what the room shows from the stores.
///
/// The room itself never waits: the furniture works at once, and the sign, the piece count and
/// the hamper fill in when the stores answer. If a store fails, the room still works and the
/// plates fall back to what's known (RD-01).
@Observable
final class HomeModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// At least one store failed. What did load is shown.
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var content = HomeRoomContent()

    /// The source on the suitcase. Hook: the remembered source arrives with the source picker
    /// (Phase 13, FR-67). Until then Home shows the main closet.
    var source: WardrobeSource = .mainCloset

    func load(from services: NookServices?) async {
        guard let services else {
            phase = .loaded
            return
        }
        phase = .loading
        var failed = false

        let profile: Profile?
        do {
            profile = try await services.profile.profile()
        } catch {
            profile = nil
            failed = true
        }

        let garments: [Garment]?
        do {
            garments = try await services.closet.garments()
        } catch {
            garments = nil
            failed = true
        }

        var plate = SourcePlate()
        switch source {
        case .mainCloset:
            plate.pieceCount = garments.map { $0.count(where: \.isInCloset) }
        case .suitcase(let id):
            do {
                let suitcase = try await services.suitcases.suitcase(id)
                plate.kind = .suitcase(name: suitcase.name)
                if let garments {
                    plate.pieceCount = garments.count { $0.isInCloset && suitcase.contains($0.id) }
                }
            } catch {
                // A missing suitcase falls back to the main closet (PRD §7.7); the picker
                // phase decides how to tell her.
                failed = true
            }
        }

        content.signName = profile?.signName ?? (failed ? "" : nil)
        content.source = plate
        if let garments, let profile {
            content.hamper = HamperState(garments: garments, tracksLaundry: profile.preferences.tracksLaundry)
        } else {
            content.hamper = nil
        }
        phase = failed ? .failed : .loaded
    }
}
