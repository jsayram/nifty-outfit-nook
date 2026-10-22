import Foundation
import Models
import Observation

/// Try it on for one look (RD-06), from Your looks or look detail.
///
/// The sheet says what will happen before anything does. A picture is made only when she taps
/// Make a picture (RD-06.2), and it's kept in the picture store before the sheet says it's ready
/// (PRD §9.2.1 step 5). When she already has a picture of exactly this look, the sheet offers it
/// first, so she doesn't make the same one twice (FR-59).
///
/// A look on Your looks may not be saved yet. Its picture needs a look to link to, so making a
/// picture saves the look too (`saveLook`), and the sheet says so first.
///
/// Stage A's pictures are simulated and free. The flow is built as the real one will run: a
/// service that can be offline or fail, and nothing used when it does (Phase 33 adds the
/// permission and cost steps).
@Observable
final class TryOnModel {
    enum Step: Equatable {
        /// What Try it on does, with Make a picture.
        case ready
        /// She already has a picture of this look (FR-59).
        case alreadyMade(TryOnPicture)
        case making
        case made(TryOnPicture)
        case failed(Failure)
    }

    enum Failure: Equatable {
        case offline
        case notCompleted
        /// The picture was made but couldn't be kept, so it isn't shown as ready.
        case notSaved
    }

    private(set) var step: Step = .ready
    /// 30a: what a picture costs her. Free while pictures are simulated on the phone. 30b: the
    /// month's pictures first, then credits.
    private(set) var allowance = TryOnAllowance.freeSimulated
    private(set) var look: Look
    /// Her garments, for drawing the picture.
    let garments: [Garment.ID: Garment]
    /// The name the picture's look goes by.
    let lookName: String
    /// Saves the look first, when it isn't saved yet (Your looks). `nil` for a saved look.
    let saveLook: (() async throws(StoreError) -> Look)?

    private var services: NookServices = .unavailable
    private var making: Task<Void, Never>?
    private let now: () -> Date

    init(
        look: Look,
        lookName: String,
        garments: [Garment.ID: Garment],
        saveLook: (() async throws(StoreError) -> Look)? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        self.look = look
        self.lookName = lookName
        self.garments = garments
        self.saveLook = saveLook
        self.now = now
    }

    /// True when making a picture also saves the look.
    var savesLook: Bool { saveLook != nil }

    /// Looks for a picture of exactly this look. If the store can't be read, it goes on as if
    /// there were none: making another is never wrong, only less thrifty.
    func start(with services: NookServices) async {
        self.services = services
        guard step == .ready else { return }
        let status = await services.subscriptions.cachedStatus()
        // 30b: what's left of the month's pictures and her credits, once pictures cost something.
        let usage = services.tryOnIsSimulated ? nil : try? await services.paid.usage()
        allowance = TryOnAllowance.current(
            status: status, picturesAreSimulated: services.tryOnIsSimulated, at: now(), usage: usage)
        let pictures = (try? await services.pictures.pictures()) ?? []
        if let existing = TryOnLinks.reusable(for: look, in: pictures) {
            step = .alreadyMade(existing)
        }
    }

    /// Make a picture (or Make another, or Try again).
    func make() {
        // 30a: never starts a paid picture without styling access or (30b) credits. The server
        // checks too (30c).
        guard step != .making, allowance.canMake else { return }
        step = .making
        making = Task { await perform() }
    }

    /// Cancel while making: nothing is kept, back to the start.
    func cancel() {
        making?.cancel()
        making = nil
        if step == .making { step = .ready }
    }

    /// Waits for a picture being made. For tests.
    func settle() async {
        await making?.value
    }

    private func perform() async {
        var picture: TryOnPicture
        do {
            picture = try await services.tryOn.makePicture(of: look, at: now())
        } catch {
            switch error {
            case .cancelled: if step == .making { step = .ready }
            case .offline: step = .failed(.offline)
            case .notCompleted: step = .failed(.notCompleted)
            }
            return
        }
        guard !Task.isCancelled else {
            await letGo(of: picture)
            return
        }
        do {
            if let saveLook {
                // Saving names the look, and the picture keeps that name with its pieces.
                look = try await saveLook()
                picture.captured.name = look.name
            }
            try await services.pictures.save(picture)
            step = .made(picture)
        } catch {
            step = .failed(.notSaved)
            await letGo(of: picture)
        }
    }

    /// A picture that was made but isn't kept leaves no file behind (Phase 22b).
    private func letGo(of picture: TryOnPicture) async {
        if let photo = picture.storedImage {
            await services.imageFiles.release([photo], deletedForGood: false)
        }
    }
}
