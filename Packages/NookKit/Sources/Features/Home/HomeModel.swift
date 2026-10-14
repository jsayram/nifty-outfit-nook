import Models
import Observation

/// Loads what the room shows from the stores and the weather service.
///
/// The room itself never waits: the furniture works at once, and the sign, the piece count,
/// the hamper and the window fill in when the services answer. If a store fails, the room
/// still works and the plates fall back to what's known (RD-01). Weather that can't be read
/// isn't a failure: the window stays plain and nothing else changes (LR-04.3).
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
    /// Pieces in her closet marked as in the wash, counted even while tracking is off, since
    /// the marks are kept (RD-11). The laundry sheet mentions them.
    private(set) var keptDirtyCount = 0

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
        // The weather comes from elsewhere (WeatherKit from Phase 29) and can be slow, so it
        // loads alongside the stores.
        async let weather = Self.currentWeather(from: services)

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
        keptDirtyCount = garments?.count { $0.isInCloset && $0.laundry == .dirty } ?? 0
        phase = failed ? .failed : .loaded
        content.weather = await weather
    }

    /// "Turn on" in the laundry sheet: saves the setting, then reloads, so the hamper changes
    /// at once (RD-11.4). Returns false if the profile couldn't be saved.
    func turnOnLaundryTracking(using services: NookServices?) async -> Bool {
        guard let services else { return false }
        do {
            var profile = try await services.profile.profile()
            profile.preferences.tracksLaundry = true
            try await services.profile.save(profile)
        } catch {
            return false
        }
        await load(from: services)
        return true
    }

    nonisolated private static func currentWeather(from services: NookServices) async -> WeatherSnapshot? {
        do {
            return try await services.weather.currentWeather()
        } catch {
            return nil
        }
    }
}
