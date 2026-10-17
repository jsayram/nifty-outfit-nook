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
    /// for the debug `-onboarding skip` flag.
    public var services: @Sendable (StartingCloset?) -> NookServices
    /// The debug `-onboarding` flag. Release builds pass `standard`.
    public var onboardingOptions: OnboardingLaunchOptions
    /// The debug `-tour` flag. Release builds pass `standard`.
    public var tourOptions: TourLaunchOptions

    public init(
        onboarding: any OnboardingStateStore,
        tours: any TourProgressStore,
        profileSettings: (any ProfileSettingsKeeper)? = nil,
        services: @escaping @Sendable (StartingCloset?) -> NookServices,
        onboardingOptions: OnboardingLaunchOptions = .standard,
        tourOptions: TourLaunchOptions = .standard
    ) {
        self.onboarding = onboarding
        self.tours = tours
        self.profileSettings = profileSettings
        self.services = services
        self.onboardingOptions = onboardingOptions
        self.tourOptions = tourOptions
    }
}

/// Decides what the app shows: onboarding on a fresh install and after Delete my data, Home
/// once she has finished it (Phase 17).
///
/// After a relaunch Home opens straight away, on the closet she chose: the sample closet comes
/// back as it ships and an empty closet starts empty again, with the name on her sign and her
/// Style Me settings as she left them. Stage A keeps nothing else she adds (see
/// `docs/onboarding.md`).
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
    }

    /// What's showing, without the services, so a view can animate between them.
    enum Screen: Hashable {
        case loading
        case onboarding(Int)
        case ready(Int)
    }

    private(set) var phase: Phase = .loading
    /// Goes up each time onboarding or the tabs open again, so every screen below is built new.
    private(set) var generation = 0

    @ObservationIgnored private let launch: AppLaunch

    init(launch: AppLaunch) {
        self.launch = launch
    }

    var screen: Screen {
        switch phase {
        case .loading: .loading
        case .onboarding: .onboarding(generation)
        case .ready: .ready(generation)
        }
    }

    /// Applies the `-onboarding` flag, then opens onboarding or Home. A store that can't be read
    /// opens onboarding, which is safe: finishing it again changes nothing she can't change later.
    func start() async {
        guard case .loading = phase else { return }
        switch launch.onboardingOptions {
        case .skip:
            open(launch.services(nil))
            return
        case .reset:
            try? await launch.onboarding.eraseAll()
            launch.profileSettings?.forget()
        case .standard:
            break
        }
        if let state = try? await launch.onboarding.state(), state.isCompleted {
            open(launch.services(state.startingCloset ?? .sample))
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
