import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Phase 17: what the app opens on, finishing onboarding, a relaunch and Delete my data. The
/// stores kept across launches are in-memory stand-ins here; `AppStateDefaultsTests` checks the
/// real ones keep their values.
@MainActor
struct AppRootModelTests {
    /// One "install": the stores that outlive a launch, and the launch options.
    struct Install {
        var onboarding = InMemoryOnboardingStore()
        var tours = InMemoryTourProgressStore()
        var configuration = FixtureConfiguration()

        func launch(_ options: OnboardingLaunchOptions = .standard) -> AppLaunch {
            let onboarding = onboarding
            let tours = tours
            let configuration = configuration
            return AppLaunch(
                onboarding: onboarding, tours: tours,
                services: { closet in
                    FixtureServices.make(
                        configuration, startingCloset: closet, tours: tours, onboarding: onboarding,
                        now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
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
                id: Garment.ID("g-new"), addedAt: ClosetTestTime.now))
        try await services.tours.record(
            TourRecord(tour: .home, version: HomeTour.version, outcome: .finished, date: ClosetTestTime.now))

        // The same install, launched again: Home straight away, on the empty closet she chose.
        // In Stage A what she added and her name are gone; the tours she saw stay seen.
        let second = await started(install)
        let again = try self.services(second)
        #expect(try await again.closet.garments().isEmpty)
        #expect(try await again.profile.profile().signName.isEmpty)
        #expect(
            try await !TourRules.startsAutomatically(.home, version: HomeTour.version, progress: again.tours.progress())
        )
    }

    @Test func aRelaunchAfterTheSampleClosetBringsItBackWithoutTheName() async throws {
        let install = Install()
        let first = await started(install)
        #expect(await first.finish(OnboardingAnswers(signName: "Lily", startingCloset: .sample)))
        let second = await started(install)
        let services = try services(second)
        #expect(try await !services.closet.garments().isEmpty)
        #expect(try await services.profile.profile().signName.isEmpty)
    }

    @Test func skipOpensTheLaunchSetAndWritesNothing() async throws {
        let install = Install()
        let model = await started(install, .skip)
        let services = try services(model)
        #expect(try await services.profile.profile().signName == "Lily")
        #expect(try await install.onboarding.state() == .fresh)
    }

    @Test func resetForgetsThatOnboardingWasFinished() async throws {
        let install = Install()
        try await install.onboarding.complete(startingCloset: .sample)
        // Finished: the tabs open straight away.
        #expect(await started(install).screen == .ready(1))
        let reset = await started(install, .reset)
        #expect(isOnboarding(reset) == .some(nil))
        #expect(try await install.onboarding.state() == .fresh)
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
}
