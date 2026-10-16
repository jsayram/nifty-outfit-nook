import Foundation
import Models
import Testing

/// What every `LookStore` does. See `StoreContract.swift` for how to run it.
public struct LookStoreContract: Sendable {
    /// Makes a store holding these looks, using this calendar for wear days.
    public typealias Factory = @Sendable ([Look], Calendar) async throws -> any LookStore

    public enum Check: String, CaseIterable, Sendable {
        case listsNewestFirst
        case readsOneOrNotFound
        case saveAddsAndReplaces
        case saveChecksANamedLook
        case updateChangesAndChecks
        case deleteRemovesIt
        case wearIsOncePerDay
        case eraseAllEmptiesIt
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    public func run(_ check: Check) async throws {
        let older = ContractData.look("l-older", name: "Office navy", createdDaysAgo: 3)
        let newer = ContractData.look("l-newer", createdDaysAgo: 1)
        let store = try await make([older, newer], ContractData.calendar)

        switch check {
        case .listsNewestFirst:
            #expect(try await store.looks().map(\.id) == ["l-newer", "l-older"])

        case .readsOneOrNotFound:
            #expect(try await store.look("l-older") == older)
            #expect(await storeError { try await store.look("nope") } == .notFound)

        case .saveAddsAndReplaces:
            try await store.save(ContractData.look("l-new"))
            #expect(try await store.looks().map(\.id) == ["l-new", "l-newer", "l-older"])
            var saved = newer
            saved.isSaved = true
            try await store.save(saved)
            #expect(try await store.look("l-newer").isSaved)
            #expect(try await store.looks().count == 3)

        case .saveChecksANamedLook:
            var look = newer
            look.name = "  Rainy office  "
            try await store.save(look)
            #expect(try await store.look("l-newer").name == "Rainy office")
            look.name = ""
            #expect(await storeError { try await store.save(look) } == .invalidName(.empty))
            // An unnamed look (an unsaved result) is fine.
            look.name = nil
            try await store.save(look)
            #expect(try await store.look("l-newer").name == nil)

        case .updateChangesAndChecks:
            let updated = try await store.update("l-older") { $0.name = " Office pink " }
            #expect(updated.name == "Office pink")
            #expect(try await store.look("l-older") == updated)
            #expect(await storeError { try await store.update("l-older") { $0.name = " " } } == .invalidName(.empty))
            #expect(try await store.look("l-older").name == "Office pink")
            #expect(await storeError { try await store.update("nope") { $0.name = "x" } } == .notFound)

        case .deleteRemovesIt:
            try await store.delete("l-older")
            #expect(try await store.looks().map(\.id) == ["l-newer"])
            #expect(await storeError { try await store.delete("l-older") } == .notFound)

        case .wearIsOncePerDay:
            try await store.recordWear(of: "l-older", on: TestTime.now)
            try await store.recordWear(of: "l-older", on: TestTime.now.addingTimeInterval(3600))
            #expect(try await store.look("l-older").wornOn == [TestTime.now])
            try await store.removeWear(of: "l-older", on: TestTime.now)
            #expect(try await store.look("l-older").wornOn.isEmpty)
            #expect(await storeError { try await store.recordWear(of: "nope", on: TestTime.now) } == .notFound)
            #expect(await storeError { try await store.removeWear(of: "nope", on: TestTime.now) } == .notFound)

        case .eraseAllEmptiesIt:
            try await store.eraseAll()
            #expect(try await store.looks().isEmpty)
            try await store.eraseAll()
        }
    }
}
