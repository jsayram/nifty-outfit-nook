import Fixtures
import Foundation
import Models
import Testing

/// Phase 17: the onboarding store in memory, and the services for each starting closet.
struct OnboardingFixtureTests {
    @Test func theStoreStartsFreshCompletesAndErases() async throws {
        let store = InMemoryOnboardingStore()
        #expect(try await store.state() == .fresh)
        #expect(try await !store.state().isCompleted)
        try await store.complete(startingCloset: .empty)
        #expect(try await store.state() == OnboardingState(isCompleted: true, startingCloset: .empty))
        try await store.eraseAll()
        #expect(try await store.state() == .fresh)
    }

    @Test func theStoreFailsWithTheOtherStores() async {
        let store = InMemoryOnboardingStore(options: StoreOptions(fails: true))
        await #expect(throws: StoreError.unavailable) { try await store.state() }
        await #expect(throws: StoreError.unavailable) { try await store.complete(startingCloset: .sample) }
    }

    private func services(
        _ configuration: FixtureConfiguration = FixtureConfiguration(), startingCloset: StartingCloset?,
        tours: (any TourProgressStore)? = nil, onboarding: (any OnboardingStateStore)? = nil
    ) -> NookServices {
        FixtureServices.make(
            configuration, startingCloset: startingCloset, tours: tours, onboarding: onboarding, now: TestTime.now,
            calendar: TestTime.calendar)
    }

    @Test func noStartingClosetIsTheLaunchSetAsItIs() async throws {
        // `-onboarding skip` and the tests: the demo with its name, as before Phase 17.
        let services = services(startingCloset: nil)
        #expect(try await services.profile.profile().signName == "Lily")
        #expect(try await !services.closet.garments().isEmpty)
    }

    @Test func theSampleClosetHasNoNameOnTheSign() async throws {
        // Her name comes from onboarding and isn't kept across launches (docs/onboarding.md).
        let sample = services(startingCloset: .sample)
        let demo = services(startingCloset: nil)
        #expect(try await sample.profile.profile().signName.isEmpty)
        #expect(try await sample.closet.garments() == demo.closet.garments())
        #expect(try await sample.looks.looks() == demo.looks.looks())
        #expect(try await sample.suitcases.suitcases() == demo.suitcases.suitcases())
        var unnamed = try await demo.profile.profile()
        unnamed.signName = ""
        #expect(try await sample.profile.profile() == unnamed)
    }

    @Test func theSampleClosetIsTheDemoEvenWhenTheLaunchIsEmpty() async throws {
        let services = services(FixtureConfiguration(set: .empty), startingCloset: .sample)
        #expect(try await !services.closet.garments().isEmpty)
    }

    @Test func theSampleClosetKeepsTheLaunchOptions() async throws {
        let services = services(FixtureConfiguration(set: .large, laundry: .full), startingCloset: .sample)
        let garments = try await services.closet.garments()
        #expect(garments.count > 2000)
        #expect(try await services.profile.profile().preferences.tracksLaundry)
    }

    @Test func theEmptyClosetIsEmpty() async throws {
        let services = services(
            FixtureConfiguration(set: .demo, behavior: .slow, photos: .samples), startingCloset: .empty)
        #expect(try await services.closet.garments().isEmpty)
        #expect(try await services.looks.looks().isEmpty)
        #expect(try await services.suitcases.suitcases().isEmpty)
        #expect(try await services.pictures.pictures().isEmpty)
        #expect(try await services.profile.profile() == Profile())
    }

    @Test func theStoresKeptAcrossLaunchesArePassedThrough() async throws {
        let tours = InMemoryTourProgressStore()
        let onboarding = InMemoryOnboardingStore()
        let services = services(startingCloset: .sample, tours: tours, onboarding: onboarding)
        try await services.tours.setShowsTipsOnNewScreens(false)
        try await services.onboarding.complete(startingCloset: .sample)
        #expect(try await !tours.progress().showsTipsOnNewScreens)
        #expect(try await onboarding.state().isCompleted)
        // Delete my data erases the ones it was given.
        _ = await services.deletion.delete(.thisDevice)
        #expect(try await tours.progress() == .fresh)
        #expect(try await onboarding.state() == .fresh)
    }
}
