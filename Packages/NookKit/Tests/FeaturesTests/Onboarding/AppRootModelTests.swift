import Fixtures
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Features

/// Phase 17: what the app opens on, finishing onboarding, a relaunch and Delete my data. The
/// stores kept across launches are in-memory stand-ins here; `AppStateDefaultsTests` checks the
/// real ones keep their values. Since the Stage A audit the name on the sign and the Style Me
/// settings are kept too.
@MainActor
struct AppRootModelTests {
    /// One "install": the stores that outlive a launch, and the launch options.
    struct Install {
        var onboarding = InMemoryOnboardingStore()
        var tours = InMemoryTourProgressStore()
        var profileSettings = InMemoryProfileSettingsKeeper()
        var configuration = FixtureConfiguration()

        /// As the app target builds it: `-onboarding skip` keeps nothing.
        func launch(_ options: OnboardingLaunchOptions = .standard) -> AppLaunch {
            let onboarding = onboarding
            let tours = tours
            let profileSettings = profileSettings
            let configuration = configuration
            return AppLaunch(
                onboarding: onboarding, tours: tours, profileSettings: profileSettings,
                services: { closet in
                    FixtureServices.make(
                        configuration, startingCloset: closet, tours: tours, onboarding: onboarding,
                        profileSettings: closet == nil ? nil : profileSettings,
                        now: TestTime.now, calendar: TestTime.calendar)
                },
                onboardingOptions: options)
        }
    }

    private func started(_ install: Install, _ options: OnboardingLaunchOptions = .standard) async -> AppRootModel {
        let model = AppRootModel(launch: install.launch(options))
        await model.start()
        return model
    }

    private func services(_ model: AppRootModel) throws -> NookServices {
        guard case .ready(let services) = model.phase else {
            Issue.record("Not on the tabs: \(model.screen)")
            throw CancellationError()
        }
        return services
    }

    private func isOnboarding(_ model: AppRootModel) -> String?? {
        if case .onboarding(let notice) = model.phase { return .some(notice) }
        return nil
    }

    @Test func aFreshInstallOpensOnboarding() async {
        let model = await started(Install())
        #expect(isOnboarding(model) == .some(nil))
        #expect(model.screen == .onboarding(1))
    }

    @Test func finishingSavesTheAnswersAndOpensHome() async throws {
        let install = Install()
        let model = await started(install)
        let answers = OnboardingAnswers(signName: "Lily", usualFit: .comfortable, startingCloset: .sample)
        #expect(await model.finish(answers))
        let services = try services(model)
        let profile = try await services.profile.profile()
        #expect(profile.signName == "Lily")
        #expect(profile.usualFit == .comfortable)
        #expect(try await !services.closet.garments().isEmpty)
        #expect(try await install.onboarding.state() == OnboardingState(isCompleted: true, startingCloset: .sample))
        // Home's tour is next: nothing seen and tips on (PRD §7.8).
        let progress = try await services.tours.progress()
        #expect(TourRules.startsAutomatically(.home, version: HomeTour.version, progress: progress))
    }

    @Test func theEmptyClosetStartsEmpty() async throws {
        let model = await started(Install())
        #expect(await model.finish(OnboardingAnswers(startingCloset: .empty)))
        let services = try services(model)
        #expect(try await services.closet.garments().isEmpty)
        #expect(try await services.looks.looks().isEmpty)
        #expect(try await services.profile.profile().signName.isEmpty)
    }

    @Test func aRelaunchOpensHomeOnTheClosetSheChose() async throws {
        let install = Install()
        let first = await started(install)
        #expect(await first.finish(OnboardingAnswers(signName: "Lily", startingCloset: .empty)))
        let services = try services(first)
        try await services.closet.save(
            GarmentDetails(name: "Sage cardigan", category: .layer).makeGarment(
                id: Garment.ID("g-new"), addedAt: TestTime.now))
        try await services.tours.record(
            TourRecord(tour: .home, version: HomeTour.version, outcome: .finished, date: TestTime.now))

        // The same install, launched again: Home straight away, on the empty closet she chose.
        // In Stage A what she added is gone; her name and the tours she saw are kept.
        let second = await started(install)
        let again = try self.services(second)
        #expect(try await again.closet.garments().isEmpty)
        #expect(try await again.profile.profile().signName == "Lily")
        #expect(
            try await !TourRules.startsAutomatically(.home, version: HomeTour.version, progress: again.tours.progress())
        )
    }

    /// The sample closet comes back as it ships, with her name and Style Me settings as she left
    /// them. Her fit and measurements are Sensitive and stay in memory, so they're gone.
    @Test func aRelaunchKeepsHerNameAndSettingsButNotHerFit() async throws {
        let install = Install()
        let first = await started(install)
        #expect(
            await first.finish(OnboardingAnswers(signName: "Ana", usualFit: .fitted, startingCloset: .sample)))
        try await services(first).profile.update {
            $0.preferences = Preferences(pieceMode: .onlyMine, repeatWindow: .twoWeeks, tracksLaundry: true)
            $0.measurements.waist = Length(27.5, .inches)
        }

        let second = await started(install)
        let services = try services(second)
        #expect(try await !services.closet.garments().isEmpty)
        let profile = try await services.profile.profile()
        #expect(profile.signName == "Ana")
        #expect(profile.preferences == Preferences(pieceMode: .onlyMine, repeatWindow: .twoWeeks, tracksLaundry: true))
        // Her fit and measurements are back to the sample's own.
        let sample = try await FixtureServices.make(
            FixtureConfiguration(), startingCloset: .sample, now: TestTime.now, calendar: TestTime.calendar
        ).profile.profile()
        #expect(profile.usualFit == sample.usualFit)
        #expect(sample.usualFit != .fitted)
        #expect(profile.measurements == sample.measurements)
    }

    @Test func skipOpensTheLaunchSetAndWritesNothing() async throws {
        let install = Install()
        let model = await started(install, .skip)
        let services = try services(model)
        #expect(try await services.profile.profile().signName == "Lily")
        try await services.profile.update { $0.signName = "Ana" }
        #expect(try await install.onboarding.state() == .fresh)
        #expect(install.profileSettings.kept() == .none)
    }

    @Test func resetForgetsThatOnboardingWasFinished() async throws {
        let install = Install()
        try await install.onboarding.complete(startingCloset: .sample)
        install.profileSettings.keep(KeptProfileSettings(signName: "Ana"))
        // Finished: the tabs open straight away, with her name.
        let finished = await started(install)
        #expect(finished.screen == .ready(1))
        #expect(try await services(finished).profile.profile().signName == "Ana")
        let reset = await started(install, .reset)
        #expect(isOnboarding(reset) == .some(nil))
        #expect(try await install.onboarding.state() == .fresh)
        // A fresh start forgets the name and settings too.
        #expect(install.profileSettings.kept() == .none)
    }

    @Test func aFailedSaveStaysOnOnboarding() async throws {
        var install = Install()
        install.configuration = FixtureConfiguration(behavior: .storesFail)
        let model = await started(install)
        #expect(await !model.finish(OnboardingAnswers(signName: "Lily")))
        #expect(isOnboarding(model) != nil)
        #expect(try await install.onboarding.state() == .fresh)
    }

    @Test func deletingMyDataGoesBackToTheWelcome() async throws {
        let install = Install()
        let model = await started(install)
        #expect(await model.finish(OnboardingAnswers(signName: "Lily")))
        let services = try services(model)
        let generation = model.generation
        #expect(await services.deletion.delete(.thisDevice).isComplete)
        model.dataDeleted()
        #expect(isOnboarding(model) == .some(OnboardingText.deleted))
        #expect(model.generation > generation)
        #expect(try await install.onboarding.state() == .fresh)
        #expect(install.profileSettings.kept() == .none)
        // Finishing again builds a new closet.
        #expect(await model.finish(OnboardingAnswers(startingCloset: .sample)))
        #expect(try await !self.services(model).closet.garments().isEmpty)
    }

    @Test func aStoreThatCantBeReadOpensOnboarding() async {
        var install = Install()
        install.onboarding = InMemoryOnboardingStore(
            state: OnboardingState(isCompleted: true, startingCloset: .sample), options: StoreOptions(fails: true))
        let model = await started(install)
        #expect(isOnboarding(model) == .some(nil))
    }

    /// Phase 21a: a store that couldn't be opened shows what happened, and nothing else runs:
    /// not the preparation, not onboarding, not the tabs.
    @Test func aStoreProblemShowsInsteadOfTheApp() async throws {
        let prepared = Flag()
        let install = Install()
        var launch = install.launch()
        launch.storeProblem = .newerVersion
        launch.prepare = { prepared.set() }
        let model = AppRootModel(launch: launch)
        await model.start()
        guard case .storeProblem(.newerVersion) = model.phase else {
            Issue.record("Expected the store problem, got \(model.screen)")
            return
        }
        #expect(!prepared.isSet)
        #expect(try await install.onboarding.state() == .fresh)
    }

    /// The preparation (moving the Stage A suite in) runs before onboarding is read.
    @Test func preparationRunsBeforeAnythingIsRead() async throws {
        let install = Install()
        var launch = install.launch()
        let onboarding = install.onboarding
        launch.prepare = { try? await onboarding.complete(startingCloset: .sample) }
        let model = AppRootModel(launch: launch)
        await model.start()
        #expect(model.screen == .ready(1))
    }

    /// `-onboarding reset` is a fresh install for her data in the store too.
    @Test func resetAlsoErasesHerStoredData() async throws {
        let install = Install()
        let closet = InMemoryClosetStore(
            garments: [Garment(id: "g1", name: "Kept tee", category: .top, addedAt: TestTime.now)],
            calendar: TestTime.calendar)
        var launch = install.launch(.reset)
        launch.erasedOnReset = [closet]
        let model = AppRootModel(launch: launch)
        await model.start()
        #expect(try await closet.garments().isEmpty)
    }
}

/// Set once, from any task.
private final class Flag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}
