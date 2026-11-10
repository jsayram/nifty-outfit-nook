#if DEBUG
    import Features
    import Fixtures
    import Foundation
    import Models
    import Networking
    import Services
    import Synchronization

    /// N4, debug builds only: launch flags that make every loading, error and empty state reachable
    /// on demand, for screenshots and UI tests. With `-fake-backend` everything stays in the fakes.
    ///
    /// - `-hold <scope>` and `-fail <scope>[=<variant>]`, with `-faults-wait`: see `DebugFaults`. The
    ///   wrappers below give the real services on the phone (backups, the try-on steps, the screenshot
    ///   cleaner, her own photos) and the fake backend's services their scopes.
    /// - `-store-problem newer-version|not-enough-space|update-failed|could-not-open`: the closet
    ///   recovery screen, as if the store couldn't be opened.
    /// - `-closet own`: with `-onboarding skip`, her own closet in the store, as Release has, instead
    ///   of the sample closet.
    /// - `-no-sample-closet`: onboarding as Release has it, with no sample closet to choose.
    /// - `-cloud-unavailable`: the cloud features say they aren't available, as in a Release build
    ///   with no backend settings.
    /// - `-backend-mode <id>`: the fake backend behaves as the gateway lab's mode `id` says (such as
    ///   `offline` or `rateLimited`), from the end of launch.
    /// - `-fake-icloud off|on|problem`: a stand-in for iCloud sync on her own closet, so the iCloud
    ///   screen can be seen without an iCloud build.
    /// - `-fake-picked-photo <garment photo>` and `-fake-picked-backup sample|junk`: what the system
    ///   pickers would hand over (`DebugPickedPhoto`, `DebugPickedBackup`).
    enum DebugCaptureHooks {
        static func value(after flag: String, in arguments: [String]) -> String? {
            DebugLaunchArgument.value(after: flag, in: arguments)
        }

        /// `-store-problem <problem>`.
        static func storeProblem(_ arguments: [String]) -> StoreOpenProblem? {
            switch value(after: "-store-problem", in: arguments) {
            case "newer-version": .newerVersion
            case "not-enough-space": .notEnoughSpace
            case "update-failed": .updateFailed
            case "could-not-open": .couldNotOpen
            default: nil
            }
        }

        /// `-closet own`.
        static func opensOwnCloset(_ arguments: [String]) -> Bool {
            value(after: "-closet", in: arguments) == "own"
        }

        /// `-no-sample-closet`.
        static func offersSampleCloset(_ arguments: [String]) -> Bool {
            !arguments.contains("-no-sample-closet")
        }

        /// `-cloud-unavailable`.
        static func cloudUnavailable(_ arguments: [String]) -> Bool {
            arguments.contains("-cloud-unavailable")
        }

        /// `-fake-picked-photo <asset>`: a garment photo from the sample wardrobe, never a person.
        @MainActor
        static func installPickedPhoto(_ arguments: [String]) {
            guard let asset = value(after: DebugPickedPhoto.launchArgument, in: arguments) else { return }
            DebugPickedPhoto.data = SampleWardrobe.garmentPhotoData(asset)
        }

        /// `-backend-mode <id>`, after the launch's own sign-ins, which need the fake backend working.
        @MainActor
        static func applyBackendMode(_ arguments: [String]) {
            guard let id = value(after: "-backend-mode", in: arguments), let controls = AppGateway.labControls
            else { return }
            controls.setMode(id)
        }

        /// `-fake-icloud off|on|problem`, or nil.
        static func iCloud(_ arguments: [String]) -> (any ICloudSyncService)? {
            switch value(after: "-fake-icloud", in: arguments) {
            case "off": DebugICloudSync(state: .off, problem: nil)
            case "on": DebugICloudSync(state: .on, problem: nil)
            case "problem": DebugICloudSync(state: .on, problem: .storageFull)
            default: nil
            }
        }

        // MARK: Wrapping

        /// Wraps the services `-hold` and `-fail` reach that aren't fakes already: the phone's own
        /// steps (backups, the try-on steps, the screenshot cleaner, her own photos) and the fake
        /// backend's notes and reports.
        static func wrap(_ services: inout NookServices) {
            let faults = DebugFaults.current
            guard !faults.isEmpty else { return }
            if let backups = services.backups { services.backups = FaultingBackupService(base: backups) }
            if let pipeline = services.tryOnPipeline { services.tryOnPipeline = FaultingTryOnPipeline(base: pipeline) }
            if let checker = services.tryOnPhotoChecker {
                services.tryOnPhotoChecker = FaultingPhotoChecker(base: checker)
            }
            if services.photos.usesSystemPicker { services.photos = FaultingPhotoIntake(base: services.photos) }
            services.screenshots = FaultingScreenshotPreparer(base: services.screenshots)
            if AppGateway.fake != nil { services.feedback = FaultingFeedbackService(base: services.feedback) }
        }

        static func wrap(_ store: any TourProgressStore) -> any TourProgressStore {
            DebugFaults.current.isEmpty ? store : FaultingTourProgressStore(base: store)
        }

        static func wrap(_ store: any OnboardingStateStore) -> any OnboardingStateStore {
            DebugFaults.current.isEmpty ? store : FaultingOnboardingStore(base: store)
        }
    }

    // MARK: - Stores

    /// Throws the store error a fault asks for, for the stores kept in the store on the iPhone.
    nonisolated private func storeFault(_ store: String, _ method: String = #function) async throws(StoreError) {
        switch await DebugFaults.current.fault(for: DebugFaults.storeScopes(store: store, method: method)) {
        case .cancelled?: throw .cancelled
        case .fail?: throw .unavailable
        case nil: break
        }
    }

    /// Scopes `tours-load` and `tours-save` (App tours' switches and Reset).
    nonisolated struct FaultingTourProgressStore: TourProgressStore {
        let base: any TourProgressStore

        func progress() async throws(StoreError) -> TourProgress {
            try await storeFault("tours")
            return try await base.progress()
        }

        func record(_ record: TourRecord) async throws(StoreError) {
            try await storeFault("tours")
            try await base.record(record)
        }

        func setShowsTipsOnNewScreens(_ isOn: Bool) async throws(StoreError) {
            try await storeFault("tours")
            try await base.setShowsTipsOnNewScreens(isOn)
        }

        func forgetSeenTours() async throws(StoreError) {
            try await storeFault("tours")
            try await base.forgetSeenTours()
        }

        func eraseAll() async throws(StoreError) {
            try await storeFault("tours")
            try await base.eraseAll()
        }
    }

    /// Scopes `onboarding-load` and `onboarding-save` (finishing onboarding).
    nonisolated struct FaultingOnboardingStore: OnboardingStateStore {
        let base: any OnboardingStateStore

        func state() async throws(StoreError) -> OnboardingState {
            try await storeFault("onboarding")
            return try await base.state()
        }

        func complete(startingCloset closet: StartingCloset) async throws(StoreError) {
            try await storeFault("onboarding")
            try await base.complete(startingCloset: closet)
        }

        func eraseAll() async throws(StoreError) {
            try await base.eraseAll()
        }
    }

    // MARK: - Backups

    /// Scopes `export`, `check` and `restore`. Variants: `space` (not enough space), `damaged`,
    /// `newer` (a newer version's copy), `not-backup`, `wrong-passphrase`; anything else is `failed`.
    nonisolated struct FaultingBackupService: BackupService {
        let base: any BackupService

        private func fault(_ scope: String) async throws(BackupError) {
            switch await DebugFaults.current.fault(for: [scope]) {
            case .cancelled?: throw .failed
            case .fail(let failure)?:
                switch failure.variant {
                case "space": throw .notEnoughSpace(needed: 2_400_000_000)
                case "damaged": throw .damaged
                case "newer": throw .newerVersion
                case "not-backup": throw .notABackup
                case "wrong-passphrase": throw .wrongPassphrase
                default: throw .failed
                }
            case nil: break
            }
        }

        func summary() async throws(BackupError) -> BackupSummary { try await base.summary() }
        func makePassphrase() -> String { base.makePassphrase() }

        func export(passphrase: String) async throws(BackupError) -> BackupFile {
            try await fault("export")
            return try await base.export(passphrase: passphrase)
        }

        func discard(_ file: BackupFile) async { await base.discard(file) }

        func check(_ url: URL, passphrase: String) async throws(BackupError) -> BackupPreview {
            try await fault("check")
            return try await base.check(url, passphrase: passphrase)
        }

        func restore(_ preview: BackupPreview, as mode: RestoreMode) async throws(BackupError) -> RestoreOutcome {
            try await fault("restore")
            return try await base.restore(preview, as: mode)
        }

        func discardChecked() async { await base.discardChecked() }
        func undoAvailable() async -> UndoRestore? { await base.undoAvailable() }
        func undoRestore() async throws(BackupError) { try await base.undoRestore() }
    }

    // MARK: - Try-on

    /// Scopes `tryon-prepare` (the steps on the phone: held, it stays on "Hiding your face") and
    /// `tryon-send` (the paid job: held, it stays on "Dressing you"). `tryon-prepare` variants name a
    /// refusal: `no-person`, `no-face`, `several`, `outline`, `unavailable` (the checks couldn't
    /// run), `no-photos`; anything else is a face still visible. `tryon-send` variants: `limited`,
    /// `quota`, `paused`, `busy`, `access`; anything else didn't finish.
    nonisolated struct FaultingTryOnPipeline: TryOnPipeline {
        let base: any TryOnPipeline

        func prepare(
            photo: PhotoReference, pieces: [Garment], progress: @escaping @MainActor @Sendable (TryOnStage) -> Void
        ) async throws(TryOnPrepareProblem) -> TryOnUpload {
            let faults = DebugFaults.current
            if !faults.isEmpty {
                // Held, the loading screen shows the first step on the phone.
                if faults.isArmed, faults.holds.contains("tryon-prepare") || faults.holds.contains("all") {
                    await progress(.hidingFace)
                }
                switch await faults.fault(for: ["tryon-prepare"]) {
                case .cancelled?: throw .checksUnavailable
                case .fail(let failure)?:
                    switch failure.variant {
                    case "no-person": throw .noPerson
                    case "no-face": throw .noFace
                    case "several": throw .severalPeople
                    case "outline": throw .unclearOutline
                    case "unavailable": throw .checksUnavailable
                    case "no-photos": throw .noGarmentPhotos
                    default: throw .faceStillVisible
                    }
                case nil: break
                }
            }
            return try await base.prepare(photo: photo, pieces: pieces, progress: progress)
        }

        private func sendFault() async throws(CloudLimitProblem) {
            switch await DebugFaults.current.fault(for: ["tryon-send"]) {
            case .cancelled?: throw .didNotFinish(retryAfterSeconds: nil)
            case .fail(let failure)?:
                switch failure.variant {
                case "limited": throw .rateLimited(retryAfterSeconds: 60)
                case "quota":
                    throw .quotaExceeded(category: .tryOn, resetAt: Date().addingTimeInterval(86_400))
                case "paused": throw .paused(feature: .tryOn, retryAfterSeconds: nil)
                case "busy": throw .busy(retryAfterSeconds: 30)
                case "access": throw .needsStylingAccess
                default: throw .didNotFinish(retryAfterSeconds: nil)
                }
            case nil: break
            }
        }

        func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String)
            async throws(CloudLimitProblem) -> Data
        {
            try await sendFault()
            return try await base.dress(upload, consentVersion: consentVersion, idempotencyKey: idempotencyKey)
        }

        func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String, link: ActionLink)
            async throws(CloudLimitProblem) -> Data
        {
            try await sendFault()
            return try await base.dress(
                upload, consentVersion: consentVersion, idempotencyKey: idempotencyKey, link: link)
        }

        func restore(_ dressed: Data, upload: TryOnUpload) async throws(TryOnError) -> PhotoReference {
            try await base.restore(dressed, upload: upload)
        }

        func keepFaceless(_ dressed: Data) async -> PhotoReference? { await base.keepFaceless(dressed) }

        func discard(_ upload: TryOnUpload, keepingSent: Bool) async {
            await base.discard(upload, keepingSent: keepingSent)
        }
    }

    /// Scope `photo-check`: the check of a new try-on photo. Held, it stays on "Checking"; failed, the
    /// checks couldn't run (`-fail photo-check=no-person` and the other `tryon-prepare` variants pick
    /// a refusal instead).
    nonisolated struct FaultingPhotoChecker: TryOnPhotoChecking {
        let base: any TryOnPhotoChecking

        func check(_ photo: PhotoReference) async -> TryOnPhotoCheck {
            switch await DebugFaults.current.fault(for: ["photo-check"]) {
            case .cancelled?: return .problem(.checksUnavailable)
            case .fail(let failure)?:
                switch failure.variant {
                case "no-person": return .problem(.noPerson)
                case "no-face": return .problem(.noFace)
                case "several": return .problem(.severalPeople)
                case "outline": return .problem(.unclearOutline)
                case "face-visible": return .problem(.faceStillVisible)
                default: return .problem(.checksUnavailable)
                }
            case nil: return await base.check(photo)
            }
        }
    }

    // MARK: - Photos and screenshots

    /// Scope `photo`, for her own photos: held, the photo stays loading; failed, it couldn't be saved
    /// (`-fail photo=unreadable`: couldn't be read).
    nonisolated struct FaultingPhotoIntake: PhotoIntake {
        let base: any PhotoIntake

        var sources: [PhotoSource] { base.sources }
        var usesSystemPicker: Bool { base.usesSystemPicker }

        private func fault() async throws(PhotoIntakeError) {
            switch await DebugFaults.current.fault(for: ["photo"]) {
            case .cancelled?: throw .cancelled
            case .fail(let failure)?: throw failure.variant == "unreadable" ? .unreadable : .notSaved
            case nil: break
            }
        }

        func photo(from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference {
            try await fault()
            return try await base.photo(from: source)
        }

        func keep(_ data: Data, from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference {
            try await fault()
            return try await base.keep(data, from: source)
        }

        func discard(_ photo: PhotoReference) async { await base.discard(photo) }
    }

    /// Scope `screenshot`: Send feedback's screenshot. Held, "Getting your screenshot ready" stays;
    /// failed, it couldn't be read (`-fail screenshot=too-large`: too large).
    nonisolated struct FaultingScreenshotPreparer: FeedbackScreenshotPreparing {
        let base: any FeedbackScreenshotPreparing

        func prepare(_ data: Data) async throws(FeedbackScreenshotProblem) -> FeedbackScreenshot {
            switch await DebugFaults.current.fault(for: ["screenshot"]) {
            case .cancelled?: throw .unreadable
            case .fail(let failure)?: throw failure.variant == "too-large" ? .tooLarge : .unreadable
            case nil: return try await base.prepare(data)
            }
        }
    }

    // MARK: - Fake backend

    /// Scopes `send` (Send feedback) and `report` (Report a problem). Held, the button stays on
    /// "Sending"; failed, with a variant naming the answer: `offline`, `timed-out`, `signed-out`,
    /// `limited`, `paused` (sending notes is paused), `screenshot` (the screenshot was refused),
    /// `update`, or anything else for a server error.
    nonisolated struct FaultingFeedbackService: FeedbackService {
        let base: any FeedbackService

        private func fault(_ scope: String) async throws(FeedbackSendProblem) {
            switch await DebugFaults.current.fault(for: [scope]) {
            case .cancelled?: throw .offline
            case .fail(let failure)?:
                switch failure.variant {
                case "offline": throw .offline
                case "timed-out": throw .timedOut
                case "signed-out": throw .signedOut
                case "limited": throw .rateLimited(retryAfterSeconds: 600)
                case "paused": throw .unavailable(retryAfterSeconds: nil)
                case "screenshot": throw .screenshotRefused
                case "update": throw .updateRequired
                default: throw .serverError
                }
            case nil: break
            }
        }

        func canSend() async -> Bool { await base.canSend() }

        func send(_ submission: FeedbackSubmission) async throws(FeedbackSendProblem) -> FeedbackReceipt {
            try await fault("send")
            return try await base.send(submission)
        }

        func sendReport(_ submission: AIReportSubmission) async throws(FeedbackSendProblem) -> FeedbackReceipt {
            try await fault("report")
            return try await base.sendReport(submission)
        }
    }

    // MARK: - iCloud

    /// A stand-in for iCloud sync on her own closet (`-fake-icloud`), so the iCloud screen, its
    /// problem note and its turn on and turn off questions can be seen without an iCloud build.
    /// Nothing talks to CloudKit.
    nonisolated final class DebugICloudSync: ICloudSyncService {
        private let current: Mutex<ICloudSyncStatus>

        init(state: ICloudSyncStatus.State, problem: ICloudProblem?) {
            current = Mutex(
                ICloudSyncStatus(
                    state: state, waitingChanges: problem == nil ? 0 : 12, waitingPhotos: problem == nil ? 0 : 4,
                    problem: problem, lastConfirmed: state == .on ? Date().addingTimeInterval(-3_600) : nil,
                    estimatedBytes: 48_000_000, includesBodyData: true))
        }

        var mayHaveCopy: Bool { current.withLock { $0.state != .off } }
        func deleteCopy() async -> DeletionOutcome { .deleted }
        func status() async -> ICloudSyncStatus { current.withLock { $0 } }

        func turnOn() async -> ICloudTurnOnResult {
            current.withLock { $0.state = .on }
            return .on
        }

        func turnOff(deletingCopy: Bool) async -> DeletionOutcome {
            current.withLock { $0 = ICloudSyncStatus(state: .off) }
            return .deleted
        }

        func answer(_ choice: ICloudChoice) async {}
        func syncNow() async {}
    }
#endif
