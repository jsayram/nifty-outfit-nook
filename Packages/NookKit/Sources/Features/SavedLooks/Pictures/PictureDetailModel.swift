import Foundation
import Models
import Observation

/// One try-on picture, opened from the Pictures tab or its look (Phase 12b, RD-08.2).
///
/// It shows the picture large with Simulated, when it was made, and the look it came from: See
/// the look while the look is in Saved Looks, a note when the look changed since or left. Delete
/// picture takes it out, with Undo; its look is never touched.
@Observable
final class PictureDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// A store failed. The screen shows its error state with Try again.
        case failed
        /// The picture is gone (deleted on another screen).
        case missing
    }

    let pictureID: TryOnPicture.ID
    private(set) var phase: Phase = .loading
    private(set) var item: SavedPictureItem?
    private(set) var garments: [Garment.ID: Garment] = [:]

    private var services: NookServices = .unavailable
    @ObservationIgnored private var loads = LoadGeneration()
    private let now: () -> Date
    private let calendar: Calendar

    init(pictureID: TryOnPicture.ID, now: @escaping () -> Date = { .now }, calendar: Calendar = .current) {
        self.pictureID = pictureID
        self.now = now
        self.calendar = calendar
    }

    // MARK: Loading

    /// Reads the picture, its look and the garments. Runs again each time the screen appears, so
    /// a look changed or deleted meanwhile shows.
    func load(from services: NookServices) async {
        self.services = services
        let load = loads.begin()
        if item == nil { phase = .loading }
        do {
            async let pictureList = services.pictures.pictures()
            async let lookList = services.looks.looks()
            async let garmentList = services.closet.garments()
            let (pictures, looks, garments) = try await (pictureList, lookList, garmentList)
            guard loads.isCurrent(load) else { return }
            show(pictures: pictures, looks: looks, garments: garments)
        } catch {
            guard loads.isCurrent(load) else { return }
            phase = .failed
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(pictures: [TryOnPicture], looks: [Look], garments: [Garment]) {
        self.garments = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let looksByID = Dictionary(looks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        item = pictures.first { $0.id == pictureID }.map {
            SavedPictureItem($0, looks: looksByID, garments: self.garments)
        }
        phase = item == nil ? .missing : .loaded
    }

    // MARK: What the screen shows

    /// "Simulated · Made 28 Aug".
    func facts(locale: Locale) -> String {
        guard let item else { return "" }
        let made = TryOnText.made(item.picture.createdAt, now: now(), calendar: calendar, locale: locale)
        // 33a: a real picture isn't simulated.
        return item.picture.isReal ? made : [SharedText.simulated, made].joined(separator: " · ")
    }

    /// The look to open with See the look, while it's in Saved Looks.
    var look: Look? { item?.look }

    /// What's said about the look under its name, if anything: it changed, or it left.
    var linkNote: String? {
        switch item?.status {
        case .changed: TryOnText.earlierVersion
        case .notSaved: TryOnText.lookNotSaved
        case .current, nil: nil
        }
    }

    // MARK: Delete

    /// Delete picture. Returns what Undo needs.
    func delete() async throws(StoreError) -> PictureRemoval {
        guard let item else { throw .unavailable }
        let removal = PictureRemoval(picture: item.picture)
        try await services.pictures.delete(removal.picture.id)
        self.item = nil
        phase = .missing
        return removal
    }
}

/// A picture she deleted, and how to put it back. Undo keeps the same ID, so it's linked to its
/// look again.
struct PictureRemoval: Hashable {
    let picture: TryOnPicture

    func undo(in store: any TryOnPictureStore) async throws(StoreError) {
        try await store.save(picture)
    }
}
