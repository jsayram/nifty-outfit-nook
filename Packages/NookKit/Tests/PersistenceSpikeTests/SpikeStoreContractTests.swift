import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

/// Gate 1 of the spike: SwiftData stores pass the same contract suites as the in-memory stores,
/// on a real store file. Closet, looks and suitcases are the stores with lists, references and
/// unique names; the others hold one record or a few flags (Phase 20a).
struct SpikeStoreContractTests {
    @Test(arguments: ClosetStoreContract.Check.allCases)
    func closet(_ check: ClosetStoreContract.Check) async throws {
        try await ClosetStoreContract { garments, calendar in
            let store = SwiftDataClosetStore(container: try Self.container(), calendar: calendar)
            for garment in garments { try await store.save(garment) }
            return store
        }.run(check)
    }

    @Test(arguments: LookStoreContract.Check.allCases)
    func looks(_ check: LookStoreContract.Check) async throws {
        try await LookStoreContract { looks, calendar in
            let store = SwiftDataLookStore(container: try Self.container(), calendar: calendar)
            for look in looks { try await store.save(look) }
            return store
        }.run(check)
    }

    @Test(arguments: SuitcaseStoreContract.Check.allCases)
    func suitcases(_ check: SuitcaseStoreContract.Check) async throws {
        try await SuitcaseStoreContract { suitcases in
            let store = SwiftDataSuitcaseStore(modelContainer: try Self.container())
            for suitcase in suitcases { try await store.restore(suitcase) }
            return store
        }.run(check)
    }

    /// Every field of every demo and large-closet garment comes back exactly as saved.
    @Test func everyFixtureGarmentRoundTrips() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let garments =
            FixtureSet.demo.data(now: SpikeSeed.epoch, calendar: calendar).garments
            + FixtureSet.large.data(now: SpikeSeed.epoch, calendar: calendar).garments.prefix(300)
        let store = SwiftDataClosetStore(container: try Self.container(), calendar: calendar)
        for garment in garments { try await store.save(garment) }
        let read = Dictionary(uniqueKeysWithValues: try await store.garments().map { ($0.id, $0) })
        for garment in garments {
            #expect(read[garment.id] == (try StoreValidation.garment(garment)))
        }
    }

    /// A store on disk in its own temporary folder.
    static func container() throws -> ModelContainer {
        try SpikeMigrationCoordinator(location: try SpikeStoreLocation.temporary("contract")).container()
    }
}
