import Foundation
import Models
import Observation

/// Profile and Fit and measurements (Phase 14a): her sign name, the usual Style Me choices, her
/// usual fit, measurements, the pieces that fit her well and the try-on photo.
///
/// One model serves Profile and the Fit screen it pushes, so a change on one shows on the other.
/// Every change is one `ProfileStore.update`, so a setting changed on another screen in the
/// meantime (Track laundry, the remembered source) is never overwritten.
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

    /// Stage A's stand-in for the try-on photo: an example, never a real photo of her. Where real
    /// photos are on (Phase 22a) she picks her own instead; Phase 33 brings the image service.
    nonisolated static let exampleTryOnPhoto = PhotoReference.sample("try-on-example")

    private(set) var phase: Phase = .loading
    private(set) var profile = Profile()
    /// The region, for the units she starts with and how numbers are written.
    private(set) var locale = Locale.current
    /// Pieces in her closet still marked as in the wash, kept while tracking is off (RD-11).
    /// Track laundry's line and toast mention them.
    private(set) var keptDirtyCount = 0
    /// 30a: her styling subscription, for the Styling access row.
    private(set) var subscription = SubscriptionState.none
    /// 30b: she has the complimentary unlock.
    private(set) var isComplimentary = false
    /// The clock for the subscription's dates. Tests fix it.
    @ObservationIgnored var now: () -> Date = { .now }
    @ObservationIgnored private var loads = LoadGeneration()

    // MARK: Loading

    /// Release: Profile's account row. `nil` hides it (no sign-in in this build, previews).
    enum Account: Equatable {
        case signedIn
        case signedOut
        /// A build with no backend: signing in isn't available right now.
        case unavailable
    }

    private(set) var account: Account?

    /// Release: reads whether she's signed in, for the account row.
    func loadAccount(from services: NookServices) async {
        if services.cloudUnavailable {
            account = .unavailable
        } else if services.offersSignIn {
            account = await services.account.isSignedIn() ? .signedIn : .signedOut
        } else {
            account = nil
        }
    }

    /// Release: Sign out from Profile. Her closet and everything on the phone stay.
    func signOut(in services: NookServices) async {
        await services.account.signOut()
        await loadAccount(from: services)
    }

    /// Sets the account row directly, for tests that hand data straight in.
    func show(account: Account?) {
        self.account = account
    }

    func load(from services: NookServices, locale: Locale) async {
        self.locale = locale
        await loadAccount(from: services)
        let load = loads.begin()
        if phase != .loaded { phase = .loading }
        do {
            let profile = try await services.profile.profile()
            guard loads.isCurrent(load) else { return }
            show(profile, locale: locale)
        } catch {
            guard loads.isCurrent(load) else { return }
            if phase != .loaded { phase = .failed }
            return
        }
        // Only for Track laundry's words, so Profile still shows if the closet can't be read.
        if let garments = try? await services.closet.garments(), loads.isCurrent(load) {
            keptDirtyCount = Self.dirtyCount(in: garments)
        }
        // StoreKit's own records, read on the phone. The cached status shows first.
        let cached = await services.subscriptions.cachedStatus()
        subscription = cached.effectiveState(at: now())
        isComplimentary = cached.isComplimentary
        let fresh = await services.subscriptions.refresh()
        if loads.isCurrent(load) {
            subscription = fresh.effectiveState(at: now())
            isComplimentary = fresh.isComplimentary
        }
    }

    /// Sets the subscription state directly, for tests that hand data straight in.
    func show(subscription: SubscriptionState, isComplimentary: Bool = false) {
        self.subscription = subscription
        self.isComplimentary = isComplimentary
    }

    /// Pieces in her closet marked as in the wash, whether or not tracking is on.
    nonisolated static func dirtyCount(in garments: [Garment]) -> Int {
        garments.count { $0.isInCloset && $0.laundry == .dirty }
    }

    /// Sets the dirty marks count directly, for tests that hand data straight in.
    func show(keptDirtyCount: Int) {
        self.keptDirtyCount = keptDirtyCount
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
    func saveName(_ text: String, in services: NookServices) async -> String? {
        guard let name = try? NameRules.signName(text) else { return nil }
        let saved = await change(in: services) { $0.signName = name }
        return saved?.signName
    }

    // MARK: Style Me's usual choices (LR-03, LR-10, LR-18)

    func setPieceMode(_ mode: PieceMode, in services: NookServices) async -> Bool {
        await change(in: services) { $0.preferences.pieceMode = mode } != nil
    }

    func setRepeatWindow(_ window: RepeatWindow, in services: NookServices) async -> Bool {
        await change(in: services) { $0.preferences.repeatWindow = window } != nil
    }

    func setUsualFit(_ fit: Comfort, in services: NookServices) async -> Bool {
        await change(in: services) { $0.usualFit = fit } != nil
    }

    /// Track laundry (RD-11). Turning it off keeps every dirty mark, so turning it on again
    /// brings them back (RD-11.2). Home's hamper and Closet's Laundry tile follow when they next
    /// appear, which is as soon as Profile closes.
    func setTracksLaundry(_ isOn: Bool, in services: NookServices) async -> Bool {
        await change(in: services) { $0.preferences.tracksLaundry = isOn } != nil
    }

    func setUnits(_ units: MeasurementUnits, in services: NookServices) async -> Bool {
        await change(in: services) { $0.units = units } != nil
    }

    // MARK: Measurements (PRD §10.1)

    /// Saves one length field, or empties it with `nil`. The value was checked by
    /// `MeasurementEntry`; the store checks it again.
    func save(_ length: Length?, for field: MeasurementField, in services: NookServices) async -> Bool {
        await change(in: services) { $0.measurements.set(length, for: field) } != nil
    }

    func save(weight: Weight?, in services: NookServices) async -> Bool {
        await change(in: services) { $0.measurements.weight = weight } != nil
    }

    func clear(_ field: MeasurementField, in services: NookServices) async -> Bool {
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
    func add(_ piece: FitPiece, in services: NookServices) async -> Bool {
        await change(in: services) { $0.fitPieces.append(piece) } != nil
    }

    /// Removes a fitting piece and returns it with its place, for Undo.
    func remove(_ id: FitPiece.ID, in services: NookServices) async -> RemovedFitPiece? {
        guard let index = profile.fitPieces.firstIndex(where: { $0.id == id }) else { return nil }
        let piece = profile.fitPieces[index]
        guard await change(in: services, { $0.fitPieces.removeAll { $0.id == id } }) != nil else { return nil }
        return RemovedFitPiece(piece: piece, index: index)
    }

    /// Undo: puts the piece back where it was.
    func restore(_ removed: RemovedFitPiece, in services: NookServices) async -> Bool {
        await change(in: services) { profile in
            guard !profile.fitPieces.contains(where: { $0.id == removed.piece.id }) else { return }
            profile.fitPieces.insert(removed.piece, at: min(removed.index, profile.fitPieces.count))
        } != nil
    }

    // MARK: Your try-on photo (RD-06)

    /// The photo shown on the sheet: hers, or nothing.
    var tryOnPhoto: PhotoReference? { profile.tryOnPhoto }

    /// Uses the example photo (Stage A's stand-in). No camera, no photo library, nothing uploaded.
    func useExamplePhoto(in services: NookServices) async -> Bool {
        await replacePhoto(with: Self.exampleTryOnPhoto, in: services)
    }

    /// Her own photo, taken with the app's camera or picked from Photos (Phase 22a, 33b): kept
    /// without its metadata (the same intake as any photo), then checked on the phone with the
    /// same fail-closed checks try-on runs (`TryOnPhotoChecking`). Nothing is her try-on photo yet:
    /// she sees what the check found first, and then `saveTryOnPhoto` or `discardTryOnPhoto`.
    /// `nil` when the photo couldn't be read or kept.
    func prepareTryOnPhoto(_ picked: PickedPhoto, in services: NookServices) async -> TryOnPhotoCandidate? {
        let photo: PhotoReference
        do {
            let data = try await picked.load()
            photo = try await services.photos.keep(data, from: picked.source)
        } catch {
            return nil
        }
        return TryOnPhotoCandidate(
            photo: photo, source: picked.source, check: await checkTryOnPhoto(photo, in: services))
    }

    /// Runs the checks again. Where nothing checks photos (the example, most tests) every photo is
    /// fine.
    func checkTryOnPhoto(_ photo: PhotoReference, in services: NookServices) async -> TryOnPhotoCheck {
        guard let checker = services.tryOnPhotoChecker else { return .fine(tips: []) }
        return await checker.check(photo)
    }

    /// Makes the checked photo her try-on photo. The photo it replaces is deleted from the iPhone
    /// at once, since it's Sensitive and nothing else points to it. If the profile can't be saved,
    /// the new copy is deleted and the old photo stays.
    func saveTryOnPhoto(_ candidate: TryOnPhotoCandidate, in services: NookServices) async -> Bool {
        guard await replacePhoto(with: candidate.photo, in: services) else {
            await services.photos.discard(candidate.photo)
            return false
        }
        return true
    }

    /// A photo she didn't use: its copy is deleted. Her current try-on photo is untouched.
    func discardTryOnPhoto(_ candidate: TryOnPhotoCandidate, in services: NookServices) async {
        await services.photos.discard(candidate.photo)
    }

    /// Removes the photo, and deletes her own photo's file. Saved try-on pictures stay
    /// (PRD §9.2.1 step 1).
    func removePhoto(in services: NookServices) async -> Bool {
        await replacePhoto(with: nil, in: services)
    }

    private func replacePhoto(with photo: PhotoReference?, in services: NookServices) async -> Bool {
        let replaced = profile.tryOnPhoto
        guard await change(in: services, { $0.tryOnPhoto = photo }) != nil else { return false }
        if let replaced, replaced != photo { await services.photos.discard(replaced) }
        return true
    }

    private func change(
        in services: NookServices, _ edit: @escaping @Sendable (inout Profile) -> Void
    ) async -> Profile? {
        do {
            let saved = try await services.profile.update(edit)
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
