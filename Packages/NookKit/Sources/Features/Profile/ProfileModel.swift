import Foundation
import Models
import Observation

/// Profile and Fit and measurements (Phase 14a): her sign name, the usual Style Me choices, her
/// usual fit, measurements, the pieces that fit her well and the try-on photo.
///
/// One model serves Profile and the Fit screen it pushes, so a change on one shows on the other.
/// Every change is one read-change-save through `ProfileStore.change`, so a setting changed on
/// another screen in the meantime (Track laundry, the remembered source) is never overwritten.
/// The store checks names and measurements again before it keeps anything.
///
/// Measurements, fitting pieces and the photo are **Sensitive** (DATA_MAP.md). Nothing here logs
/// them, and the screens that show them cover them in the app switcher (`hiddenWhenInactive`).
@Observable
final class ProfileModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The profile couldn't be read. The screen shows its error state with Try again.
        case failed
    }

    /// Stage A's stand-in for the try-on photo: an example, never a real photo of her. Phase 22a
    /// brings the system photo picker and Phase 33 the image service.
    nonisolated static let exampleTryOnPhoto = PhotoReference.sample("try-on-example")

    private(set) var phase: Phase = .loading
    private(set) var profile = Profile()
    /// The region, for the units she starts with and how numbers are written.
    private(set) var locale = Locale.current

    // MARK: Loading

    func load(from services: NookServices?, locale: Locale) async {
        self.locale = locale
        guard let services else {
            phase = .loaded
            return
        }
        if phase != .loaded { phase = .loading }
        do {
            show(try await services.profile.profile(), locale: locale)
        } catch {
            if phase != .loaded { phase = .failed }
        }
    }

    /// Sets the profile directly. Separate from `load` so tests can hand data straight in.
    func show(_ profile: Profile, locale: Locale) {
        self.profile = profile
        self.locale = locale
        phase = .loaded
    }

    // MARK: What the screens show

    /// The units Fit shows: her choice, or the region's usual ones until she picks.
    var units: MeasurementUnits {
        profile.units ?? .preferred(for: locale)
    }

    var hasTryOnPhoto: Bool { profile.tryOnPhoto != nil }

    // MARK: Name on your sign (RD-03)

    /// What's wrong with the name as typed, or `nil` when it can be saved. Empty is fine.
    func nameProblem(_ text: String) -> NameProblem? {
        do {
            _ = try NameRules.signName(text)
            return nil
        } catch {
            return error
        }
    }

    /// Saves the sign name. Returns the name as stored (trimmed), or `nil` if it wasn't saved.
    func saveName(_ text: String, in services: NookServices?) async -> String? {
        guard let name = try? NameRules.signName(text) else { return nil }
        let saved = await change(in: services) { $0.signName = name }
        return saved?.signName
    }

    // MARK: Style Me's usual choices (LR-03, LR-10, LR-18)

    func setPieceMode(_ mode: PieceMode, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.preferences.pieceMode = mode } != nil
    }

    func setRepeatWindow(_ window: RepeatWindow, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.preferences.repeatWindow = window } != nil
    }

    func setUsualFit(_ fit: Comfort, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.usualFit = fit } != nil
    }

    func setUnits(_ units: MeasurementUnits, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.units = units } != nil
    }

    // MARK: Measurements (PRD §10.1)

    /// Saves one length field, or empties it with `nil`. The value was checked by
    /// `MeasurementEntry`; the store checks it again.
    func save(_ length: Length?, for field: MeasurementField, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.measurements.set(length, for: field) } != nil
    }

    func save(weight: Weight?, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.measurements.weight = weight } != nil
    }

    func clear(_ field: MeasurementField, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.measurements.clear(field) } != nil
    }

    // MARK: Pieces that fit you well (LR-13)

    /// What's wrong with a new fitting piece, by field, or `nil` when it can be added.
    static func problems(brand: String, size: String) -> FitPieceProblems? {
        var problems = FitPieceProblems()
        do {
            _ = try MeasurementRules.fitBrand(brand)
        } catch {
            problems.brand = error
        }
        do {
            _ = try MeasurementRules.fitSize(size)
        } catch {
            problems.size = error
        }
        return problems.isEmpty ? nil : problems
    }

    /// Adds a fitting piece. Returns false when it wasn't saved.
    func add(_ piece: FitPiece, in services: NookServices?) async -> Bool {
        await change(in: services) { $0.fitPieces.append(piece) } != nil
    }

    /// Removes a fitting piece and returns it with its place, for Undo.
    func remove(_ id: FitPiece.ID, in services: NookServices?) async -> RemovedFitPiece? {
        guard let index = profile.fitPieces.firstIndex(where: { $0.id == id }) else { return nil }
        let piece = profile.fitPieces[index]
        guard await change(in: services, { $0.fitPieces.removeAll { $0.id == id } }) != nil else { return nil }
        return RemovedFitPiece(piece: piece, index: index)
    }

    /// Undo: puts the piece back where it was.
    func restore(_ removed: RemovedFitPiece, in services: NookServices?) async -> Bool {
        await change(in: services) { profile in
            guard !profile.fitPieces.contains(where: { $0.id == removed.piece.id }) else { return }
            profile.fitPieces.insert(removed.piece, at: min(removed.index, profile.fitPieces.count))
        } != nil
    }

    // MARK: Your try-on photo (RD-06, Stage A stand-in)

    /// Uses the example photo. No camera, no photo library, nothing uploaded.
    func useExamplePhoto(in services: NookServices?) async -> Bool {
        await change(in: services) { $0.tryOnPhoto = Self.exampleTryOnPhoto } != nil
    }

    /// Removes the photo. Saved try-on pictures stay (PRD §9.2.1 step 1).
    func removePhoto(in services: NookServices?) async -> Bool {
        await change(in: services) { $0.tryOnPhoto = nil } != nil
    }

    // MARK: Saving

    /// Reads, changes and saves the profile, then shows what was saved. `nil` when it failed.
    private func change(
        in services: NookServices?, _ edit: @escaping @Sendable (inout Profile) -> Void
    ) async -> Profile? {
        guard let services else {
            var profile = profile
            edit(&profile)
            self.profile = profile
            return profile
        }
        do {
            let saved = try await services.profile.change(edit)
            profile = saved
            return saved
        } catch {
            return nil
        }
    }
}

/// A fitting piece she removed and where it was, for Undo.
nonisolated struct RemovedFitPiece: Hashable, Sendable {
    let piece: FitPiece
    let index: Int
}

/// What's wrong with a new fitting piece, by field.
nonisolated struct FitPieceProblems: Hashable, Sendable {
    var brand: NameProblem?
    var size: NameProblem?

    var isEmpty: Bool { brand == nil && size == nil }
}
