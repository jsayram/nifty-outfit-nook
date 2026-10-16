import Foundation
import Models
import Testing

/// What every `SuitcaseStore` does. See `StoreContract.swift` for how to run it.
public struct SuitcaseStoreContract: Sendable {
    /// Makes a store holding these suitcases.
    public typealias Factory = @Sendable ([Suitcase]) async throws -> any SuitcaseStore

    public enum Check: String, CaseIterable, Sendable {
        case readsOneOrNotFound
        case createNeedsAUniqueName
        case updateKeepsNamesUnique
        case addsAndRemovesPieces
        case markUsedSetsTheDate
        case deleteKeepsThePieces
        case restorePutsBackTheSameSuitcase
        case eraseAllEmptiesIt
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    public func run(_ check: Check) async throws {
        let weekend = ContractData.suitcase("s-weekend", name: "Weekend", pieces: ["g1", "g2"])
        let work = ContractData.suitcase("s-work", name: "Work trip")
        let store = try await make([weekend, work])

        switch check {
        case .readsOneOrNotFound:
            #expect(try await store.suitcase("s-weekend") == weekend)
            #expect(Set(try await store.suitcases().map(\.id)) == ["s-weekend", "s-work"])
            #expect(await storeError { try await store.suitcase("nope") } == .notFound)

        case .createNeedsAUniqueName:
            let made = try await store.create(name: "  Beach  ", icon: .duffel, at: TestTime.now)
            #expect(made.name == "Beach")
            #expect(made.icon == .duffel)
            #expect(made.garmentIDs.isEmpty)
            #expect(made.createdAt == TestTime.now)
            #expect(try await store.suitcase(made.id) == made)
            #expect(
                await storeError { try await store.create(name: "weekend", icon: .rolling, at: TestTime.now) }
                    == .invalidName(.duplicate))
            #expect(
                await storeError { try await store.create(name: " ", icon: .rolling, at: TestTime.now) }
                    == .invalidName(.empty))
            #expect(try await store.suitcases().count == 3)

        case .updateKeepsNamesUnique:
            // Its own name, in another case, is fine.
            #expect(try await store.update("s-weekend") { $0.name = "WEEKEND" }.name == "WEEKEND")
            #expect(
                await storeError { try await store.update("s-weekend") { $0.name = "Work trip" } }
                    == .invalidName(.duplicate))
            #expect(try await store.suitcase("s-weekend").name == "WEEKEND")
            #expect(await storeError { try await store.update("nope") { $0.isArchived = true } } == .notFound)

        case .addsAndRemovesPieces:
            try await store.add(["g2", "g3"], to: "s-weekend")
            #expect(try await store.suitcase("s-weekend").garmentIDs == ["g1", "g2", "g3"])
            try await store.remove(["g1", "g9"], from: "s-weekend")
            #expect(try await store.suitcase("s-weekend").garmentIDs == ["g2", "g3"])
            #expect(await storeError { try await store.add(["g1"], to: "nope") } == .notFound)
            #expect(await storeError { try await store.remove(["g1"], from: "nope") } == .notFound)

        case .markUsedSetsTheDate:
            try await store.markUsed("s-work", at: TestTime.now)
            #expect(try await store.suitcase("s-work").lastUsedAt == TestTime.now)
            #expect(await storeError { try await store.markUsed("nope", at: TestTime.now) } == .notFound)

        case .deleteKeepsThePieces:
            try await store.delete("s-weekend")
            #expect(try await store.suitcases().map(\.id) == ["s-work"])
            #expect(await storeError { try await store.delete("s-weekend") } == .notFound)

        case .restorePutsBackTheSameSuitcase:
            try await store.delete("s-weekend")
            try await store.restore(weekend)
            #expect(try await store.suitcase("s-weekend") == weekend)
            // Another suitcase took the name meanwhile.
            try await store.delete("s-weekend")
            _ = try await store.create(name: "Weekend", icon: .rolling, at: TestTime.now)
            #expect(await storeError { try await store.restore(weekend) } == .invalidName(.duplicate))

        case .eraseAllEmptiesIt:
            try await store.eraseAll()
            #expect(try await store.suitcases().isEmpty)
            try await store.eraseAll()
        }
    }
}
