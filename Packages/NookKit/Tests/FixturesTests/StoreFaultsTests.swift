import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

/// N4: `-hold` and `-fail` reach the in-memory stores through `StoreOptions`, one store and one kind
/// of call at a time.
struct StoreFaultsTests {
    private static func options(_ faults: DebugFaults) -> StoreOptions {
        var options = StoreOptions()
        options.faults = faults
        return options
    }

    @Test func aFailedLoadFailsOnlyThatStoresReads() async throws {
        let options = Self.options(DebugFaults(fails: ["closet-load": ""]))
        let garment = Garment(id: .init("g-1"), name: "Tee", category: .top, colors: [.navy], addedAt: .now)
        let closet = InMemoryClosetStore(garments: [garment], calendar: .current, options: options)
        let looks = InMemoryLookStore(looks: [], calendar: .current, options: options)

        await #expect(throws: StoreError.unavailable) { try await closet.garments() }
        await #expect(throws: StoreError.unavailable) { try await closet.garment(garment.id) }
        try await closet.save(garment)
        #expect(try await looks.looks().isEmpty)
    }

    @Test func aFailedSaveLeavesReadsWorking() async throws {
        let options = Self.options(DebugFaults(fails: ["profile-save": ""]))
        let profile = InMemoryProfileStore(profile: Profile(), options: options)

        _ = try await profile.profile()
        await #expect(throws: StoreError.unavailable) { try await profile.update { $0.signName = "Lily" } }
    }

    @Test func aHeldLoadWaitsUntilCancelled() async {
        let options = Self.options(DebugFaults(holds: ["store-load"]))
        let suitcases = InMemorySuitcaseStore(suitcases: [], options: options)
        let load = Task { try await suitcases.suitcases() }
        try? await Task.sleep(for: .milliseconds(200))
        load.cancel()
        await #expect(throws: StoreError.cancelled) { try await load.value }
    }

    @Test func readsTheN4FixtureOptions() {
        let configuration = FixtureConfiguration(
            launchArguments: ["App", "-fixtures", "demo:suitcases=none:looks=unsaved:laundry=all"])
        #expect(configuration.suitcases == FixtureSuitcasesState.none)
        #expect(configuration.looks == .unsaved)
        #expect(configuration.laundry == .all)
    }

    @Test func theN4FixtureOptionsEmptyTheSuitcasesUnsaveTheLooksAndDirtyEverything() async throws {
        let services = FixtureServices.make(
            FixtureConfiguration(set: .demo, laundry: .all, suitcases: FixtureSuitcasesState.none, looks: .unsaved))
        #expect(try await services.suitcases.suitcases().isEmpty)
        let looks = try await services.looks.looks()
        #expect(!looks.isEmpty)
        #expect(looks.allSatisfy { !$0.isSaved })
        let inCloset = try await services.closet.garments().filter(\.isInCloset)
        #expect(!inCloset.isEmpty)
        #expect(inCloset.allSatisfy { $0.laundry == .dirty })
        #expect(try await services.profile.profile().remembered.source == .mainCloset)
    }
}
