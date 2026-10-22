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
/// Stage A's pictures are simulated and free. Phase 33a's real pictures (`services.tryOnPipeline`)
/// add her consent to the image provider, the steps on the phone that hide her face and swap in
/// the studio backdrop (refusing kindly when they can't be sure), and a background job (27c): she
/// can leave the sheet once the faceless photo is on its way, and the banner says when the
/// picture is ready.
@Observable
final class TryOnModel {
    enum Step: Equatable {
        /// What Try it on does, with Make a picture.
        case ready
        /// She already has a picture of this look (FR-59).
        case alreadyMade(TryOnPicture)
        /// 33a: her OK to send the faceless photo to the image provider, before anything happens.
        case consent
        /// 33a: on the phone, hiding her face and swapping in the studio backdrop. Leaving stops it
        /// and nothing is sent.
        case preparing
        /// 33a: the faceless photo is on its way as a background job. She can leave.
        case sending(AIJob.ID)
        /// 33a: the phone wouldn't send this photo. Nothing left the phone.
        case refused(TryOnPrepareProblem)
        case making
        case made(TryOnPicture)
        case failed(Failure)
    }

    enum Failure: Equatable {
        case offline
        case notCompleted
        /// The picture was made but couldn't be kept, so it isn't shown as ready.
        case notSaved
        /// 33a: a limit on the server (an allowance, a pause, busy).
        case limited(CloudLimitProblem)
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
    /// 33a: the job this sheet is showing, while it shows it.
    private var shownJob: AIJob.ID?
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

    /// 33a: real pictures, made from her try-on photo with her face kept on the phone.
    var isReal: Bool { services.tryOnPipeline != nil }

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
        // 33a: a picture of this look still being made (she left and came back) shows its job.
        if isReal, let job = services.aiJobs.job(forTryOnOf: look.id), job.state.isActive {
            watch(job.id)
            return
        }
        let pictures = (try? await services.pictures.pictures()) ?? []
        if let existing = TryOnLinks.reusable(for: look, in: pictures) {
            step = .alreadyMade(existing)
        }
    }

    /// Make a picture (or Make another, or Try again).
    func make() {
        // 30a: never starts a paid picture without styling access or (30b) credits. The server
        // checks too (30c).
        guard step != .making, step != .preparing, allowance.canMake else { return }
        if case .sending = step { return }
        guard isReal else {
            step = .making
            making = Task { await perform() }
            return
        }
        // 33a: no consent, no call, and nothing is prepared either.
        guard let consent = services.tryOnConsent.current(), consent.isCurrent else {
            step = .consent
            return
        }
        step = .preparing
        let version = consent.version
        making = Task { await prepareAndSend(consentVersion: version) }
    }

    /// 33a: Allow on the consent step: her yes is kept, then the picture is made.
    func allow() {
        services.tryOnConsent.save(TryOnConsent(agreedAt: now()))
        step = .ready
        make()
    }

    /// 33a: Not now on the consent step. Nothing was sent.
    func notNow() {
        step = .ready
    }

    /// Cancel while making: nothing is kept, back to the start. A real picture's job is stopped
    /// only by this, never by leaving the sheet.
    func cancel() {
        making?.cancel()
        making = nil
        if case .sending(let id) = step { services.aiJobs.cancel(id) }
        if step == .making || step == .preparing { step = .ready }
        if case .sending = step { step = .ready }
    }

    /// The sheet went away. A simulated picture stops (nothing is kept); preparing a real one
    /// stops before anything is sent; a real picture already on its way carries on as its job.
    func leave() {
        if let shownJob { services.aiJobs.stoppedShowing(shownJob) }
        shownJob = nil
        if case .sending = step {
            making = nil
            return
        }
        making?.cancel()
        making = nil
        if step == .making || step == .preparing { step = .ready }
    }

    // MARK: Real pictures (33a)

    private func prepareAndSend(consentVersion: String) async {
        guard let pipeline = services.tryOnPipeline else { return }
        let photo = (try? await services.profile.profile())?.tryOnPhoto ?? .noPhoto
        let pieces = look.garmentIDs.compactMap { garments[$0] }
        let upload: TryOnUpload
        do {
            upload = try await pipeline.prepare(photo: photo, pieces: pieces)
        } catch {
            if !Task.isCancelled { step = .refused(error) }
            return
        }
        // She left while the phone was preparing: nothing is sent.
        guard !Task.isCancelled else {
            await pipeline.discard(upload, keepingSent: false)
            return
        }
        if let saveLook {
            do {
                look = try await saveLook()
            } catch {
                await pipeline.discard(upload, keepingSent: false)
                step = .failed(.notSaved)
                return
            }
        }
        let job = services.aiJobs.startTryOn(
            TryOnJobRequest(look: look, upload: upload, consentVersion: consentVersion), services: services)
        watch(job.id)
    }

    /// Shows a try-on job until it finishes, here or wherever she is.
    private func watch(_ id: AIJob.ID) {
        if shownJob != id {
            if let shownJob { services.aiJobs.stoppedShowing(shownJob) }
            services.aiJobs.showing(id)
            shownJob = id
        }
        step = .sending(id)
        let jobs = services.aiJobs
        making = Task {
            let job = await jobs.finished(id)
            guard step == .sending(id), let job else { return }
            switch job.state {
            case .done:
                if let picture = job.picture { step = .made(picture) } else { step = .failed(.notSaved) }
            case .cancelled:
                step = .ready
            default:
                // The server says her consent doesn't cover where it would send the photos.
                step = job.failure == .needsConsent ? .consent : .failed(Self.failure(job.failure))
            }
        }
    }

    static func failure(_ failure: AIJob.Failure?) -> Failure {
        switch failure {
        case .offline: .offline
        case .limited(let problem): .limited(problem)
        default: .notCompleted
        }
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
        let photos = picture.storedImages
        if !photos.isEmpty { await services.imageFiles.release(photos, deletedForGood: false) }
    }
}
