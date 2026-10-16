import Models
import Observation

/// Loads what the room shows from the stores and the weather service: the sign, the source she
/// chose last on the suitcase, her last occasion on the calendar (Phase 13), the hamper, the
/// shelf frames and the window.
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

        let suitcases: [Suitcase]?
        do {
            suitcases = try await services.suitcases.suitcases()
        } catch {
            suitcases = nil
            failed = true
        }
        content.source = Self.sourcePlate(
            remembered: profile?.remembered.source ?? .mainCloset, garments: garments, suitcases: suitcases)
        content.occasion = profile?.remembered.occasion

        do {
            let looks = try await services.looks.looks()
            content.framedLooks = Self.framedLooks(from: looks, garments: garments ?? [])
        } catch {
            failed = true
        }

        content.signName = profile?.signName ?? (failed ? "" : nil)
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

    /// The suitcase's plates for the source she chose last (FR-67, RD-01.3). A suitcase that's
    /// been deleted or archived shows the main closet instead (PRD §7.7); Style Me then asks her
    /// to choose. Pieces she no longer has don't count (LR-16.1). Without the suitcases, the
    /// main closet shows with its count.
    static func sourcePlate(remembered: WardrobeSource, garments: [Garment]?, suitcases: [Suitcase]?) -> SourcePlate {
        let source = suitcases.map { SourceChoice.shown(remembered, among: $0) } ?? .mainCloset
        let count = garments.map { SourceChoice.pieces(in: source, garments: $0, suitcases: suitcases ?? []).count }
        guard let id = source.suitcaseID, let suitcase = suitcases?.first(where: { $0.id == id }) else {
            return SourcePlate(kind: .mainCloset, pieceCount: count)
        }
        return SourcePlate(kind: .suitcase(name: suitcase.name, icon: suitcase.icon), pieceCount: count)
    }

    /// Her three most recently saved looks for the shelf frames, newest first (Phase 12a).
    static func framedLooks(from looks: [Look], garments: [Garment]) -> [FramedLook] {
        let byID = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return
            looks
            .filter(\.isSaved)
            .sorted { lhs, rhs in lhs.savedDate != rhs.savedDate ? lhs.savedDate > rhs.savedDate : lhs.id < rhs.id }
            .prefix(FramedLook.frameCount)
            .map { look in
                let pieces = look.pieces.compactMap { piece -> FramedLook.Piece? in
                    switch piece.content {
                    case .garment(let id):
                        byID[id].map {
                            FramedLook.Piece(
                                category: $0.category, colors: $0.colors, photo: $0.photo, cutout: $0.cutout)
                        }
                    case .idea(let idea):
                        FramedLook.Piece(category: idea.category, colors: idea.colors, photo: .noPhoto)
                    }
                }
                return FramedLook(
                    id: look.id, name: look.name ?? SavedLooksText.unnamed(occasion: look.occasion?.title),
                    pieces: FramedLook.mainPieces(of: pieces))
            }
    }

    nonisolated private static func currentWeather(from services: NookServices) async -> WeatherSnapshot? {
        do {
            return try await services.weather.currentWeather()
        } catch {
            return nil
        }
    }
}
