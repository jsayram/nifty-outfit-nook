import Foundation
import Models
import Observation

/// What the app target hands the root at launch (Phase 17).
nonisolated public struct AppLaunch: Sendable {
    /// Whether onboarding was finished, kept across launches. The same store must be the
    /// `onboarding` of every `NookServices` that `services` makes, so Delete my data erases it.
    public var onboarding: any OnboardingStateStore
    /// The tours seen, kept across launches. Also the `tours` of every `NookServices` made.
    public var tours: any TourProgressStore
    /// The name on the sign and the Style Me settings, kept across launches (Stage A audit). The
    /// services keep them through their profile store; this is here so the debug
    /// `-onboarding reset` flag can forget them too. `nil` when nothing is kept.
    public var profileSettings: (any ProfileSettingsKeeper)?
    /// Makes the services for a starting closet. `nil` is the launch's own sample data as it is,
    /// for the debug `-onboarding skip` flag. Called only by `AppRootModel`, on the main actor, so
    /// the app's main-actor installers (diagnostics, the gateway) can run inside it.
    public var services: @MainActor @Sendable (StartingCloset?) -> NookServices
    /// The debug `-onboarding` flag. Release builds pass `standard`.
    public var onboardingOptions: OnboardingLaunchOptions
    /// The debug `-tour` flag. Release builds pass `standard`.
    public var tourOptions: TourLaunchOptions
    /// Whether onboarding offers the sample closet. Release builds ship no sample data
    /// (Phase 20a), so they pass false and onboarding starts on an empty closet.
    public var offersSampleCloset: Bool
    /// Why the store on the iPhone couldn't be opened, if it couldn't (Phase 21a). The app then
    /// shows what happened instead of onboarding or the tabs, and changes nothing.
    public var storeProblem: StoreOpenProblem?
    /// Runs once before anything is read: since Phase 21a, moving the Stage A `UserDefaults`
    /// suite into the store.
    public var prepare: @Sendable () async -> Void
    /// What the debug `-onboarding reset` flag erases besides the onboarding state and the kept
    /// settings: her data in the store, as on a fresh install (Phase 21a). The tours have their
    /// own flag.
    public var erasedOnReset: [any ErasableStore]
    /// Restore from a backup file on onboarding's welcome (Phase 21b). `nil` hides it.
    public var backups: (any BackupService)?
    /// Export a copy on the recovery screen, when the store couldn't be opened (Phase 21b).
    public var storeCopy: (any StoreCopyExporter)?
    /// Called after a restore or Undo restore, before the screens are built again: the app gives
    /// `services` fresh stores, since the old ones remember what the store held before.
    public var reload: @Sendable () -> Void

    public init(
        onboarding: any OnboardingStateStore,
        tours: any TourProgressStore,
        profileSettings: (any ProfileSettingsKeeper)? = nil,
        services: @escaping @MainActor @Sendable (StartingCloset?) -> NookServices,
        onboardingOptions: OnboardingLaunchOptions = .standard,
        tourOptions: TourLaunchOptions = .standard,
        offersSampleCloset: Bool = true,
        storeProblem: StoreOpenProblem? = nil,
        prepare: @escaping @Sendable () async -> Void = {},
        erasedOnReset: [any ErasableStore] = [],
        backups: (any BackupService)? = nil,
        storeCopy: (any StoreCopyExporter)? = nil,
        reload: @escaping @Sendable () -> Void = {}
    ) {
        self.onboarding = onboarding
        self.tours = tours
        self.profileSettings = profileSettings
        self.services = services
        self.onboardingOptions = onboardingOptions
        self.tourOptions = tourOptions
        self.offersSampleCloset = offersSampleCloset
        self.storeProblem = storeProblem
        self.prepare = prepare
        self.erasedOnReset = erasedOnReset
        self.backups = backups
        self.storeCopy = storeCopy
        self.reload = reload
    }
}

/// Why the store on the iPhone couldn't be opened (Phase 21a). Mirrors `StoreProblem` in
/// Services, which Features doesn't depend on. Nothing was reset or deleted in any of them.
nonisolated public enum StoreOpenProblem: Hashable, Sendable {
    /// Saved by a newer version of the app, or not readable by this one.
    case newerVersion
    /// Not enough free space for the safety copy an update needs.
    case notEnoughSpace
    /// An update to the store failed; the copy from before is kept.
    case updateFailed
    /// The store couldn't be opened.
    case couldNotOpen
}

/// Decides what the app shows: onboarding on a fresh install and after Delete my data, Home
/// once she has finished it (Phase 17).
///
/// After a relaunch Home opens straight away, on the closet she chose. Since Phase 21a her own
/// closet (the empty one she started, and every Release build) is kept in the store on the
/// iPhone, with everything she adds. The debug sample closet comes back as it ships, with the
/// name on her sign and her Style Me settings as she left them (see `docs/onboarding.md`).
@MainActor
@Observable
final class AppRootModel {
    enum Phase {
        /// Reading whether onboarding was finished. A moment at most.
        case loading
        /// Onboarding, with a note to show on the welcome (after Delete my data).
        case onboarding(notice: String?)
        /// The tabs, on these services.
        case ready(NookServices)
        /// The store couldn't be opened (Phase 21a). Nothing else shows.
        case storeProblem(StoreOpenProblem)
    }

    /// What's showing, without the services, so a view can animate between them.
    enum Screen: Hashable {
        case loading
        case onboarding(Int)
        case ready(Int)
        case storeProblem
    }

    private(set) var phase: Phase = .loading
    /// Goes up each time onboarding or the tabs open again, so every screen below is built new.
    private(set) var generation = 0

    @ObservationIgnored private let launch: AppLaunch

    init(launch: AppLaunch) {
        self.launch = launch
    }

    /// Whether onboarding offers the sample closet (false in Release, Phase 20a).
    var offersSampleCloset: Bool { launch.offersSampleCloset }

    var screen: Screen {
        switch phase {
        case .loading: .loading
        case .onboarding: .onboarding(generation)
        case .ready: .ready(generation)
        case .storeProblem: .storeProblem
        }
    }

    /// Applies the `-onboarding` flag, then opens onboarding or Home. A store that can't be read
    /// opens onboarding, which is safe: finishing it again changes nothing she can't change later.
    func start() async {
        guard case .loading = phase else { return }
        if let problem = launch.storeProblem {
            phase = .storeProblem(problem)
            return
        }
        await launch.prepare()
        switch launch.onboardingOptions {
        case .skip:
            open(launch.services(nil))
            return
        case .reset:
            try? await launch.onboarding.eraseAll()
            launch.profileSettings?.forget()
            for store in launch.erasedOnReset {
                try? await store.eraseAll()
            }
        case .standard:
            break
        }
        if let state = try? await launch.onboarding.state(), state.isCompleted {
            open(launch.services(state.startingCloset ?? (offersSampleCloset ? .sample : .empty)))
        } else {
            generation += 1
            phase = .onboarding(notice: nil)
        }
    }

    /// The last onboarding step: builds the closet she chose, writes her name and fit to its
    /// profile, keeps that onboarding is done, then opens Home, where Home's tour starts (PRD §7.8).
    /// Returns false, and stays on onboarding, when a save fails.
    func finish(_ answers: OnboardingAnswers) async -> Bool {
        let services = launch.services(answers.startingCloset)
        do {
            try await services.profile.update { answers.apply(to: &$0) }
            try await launch.onboarding.complete(startingCloset: answers.startingCloset)
        } catch {
            return false
        }
        open(services)
        return true
    }

    /// Restore from a backup file on the welcome. `nil` in builds and launches without backups.
    var backups: (any BackupService)? { launch.backups }

    /// Export a copy on the recovery screen.
    var storeCopy: (any StoreCopyExporter)? { launch.storeCopy }

    /// A restore or Undo restore finished: every screen is built again on fresh stores, on her
    /// own closet, where the restore finished onboarding.
    func restored() {
        launch.reload()
        open(launch.services(.empty))
    }

    /// Delete my data finished: back to the welcome, as on a fresh install, with a note.
    func dataDeleted() {
        generation += 1
        phase = .onboarding(notice: OnboardingText.deleted)
    }

    private func open(_ services: NookServices) {
        generation += 1
        phase = .ready(services)
    }
}
