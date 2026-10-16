import Foundation
import Models
import Testing

/// What every `ClosetStore` does. See `StoreContract.swift` for how to run it.
public struct ClosetStoreContract: Sendable {
    /// Makes a store holding these garments, using this calendar for wear days.
    public typealias Factory = @Sendable ([Garment], Calendar) async throws -> any ClosetStore

    public enum Check: String, CaseIterable, Sendable {
        case listsNewestFirst
        case readsOneOrNotFound
        case saveAddsAndReplaces
        case saveTrimsAndChecksTheName
        case saveRefusesBadDetails
        case updateChangesAndChecks
        case wearIsOncePerDayAndLeavesLaundry
        case wearChangesAllOrNone
        case setsLaundry
        case deleteAndRestore
        case purgesOnlyExpiredPieces
        case eraseAllEmptiesIt
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    public func run(_ check: Check) async throws {
        let calendar = ContractData.calendar
        let older = ContractData.garment("g-older", addedDaysAgo: 3)
        let newer = ContractData.garment("g-newer", addedDaysAgo: 1)
        let store = try await make([older, newer], calendar)

        switch check {
        case .listsNewestFirst:
            #expect(try await store.garments().map(\.id) == ["g-newer", "g-older"])

        case .readsOneOrNotFound:
            #expect(try await store.garment("g-older") == older)
            #expect(await storeError { try await store.garment("nope") } == .notFound)

        case .saveAddsAndReplaces:
            let added = ContractData.garment("g-new", addedDaysAgo: 0)
            try await store.save(added)
            #expect(try await store.garments().map(\.id) == ["g-new", "g-newer", "g-older"])
            var renamed = older
            renamed.name = "Renamed"
            try await store.save(renamed)
            #expect(try await store.garment("g-older").name == "Renamed")
            #expect(try await store.garments().count == 3)

        case .saveTrimsAndChecksTheName:
            var piece = older
            piece.name = "  Navy trousers  "
            try await store.save(piece)
            #expect(try await store.garment("g-older").name == "Navy trousers")
            piece.name = "   "
            #expect(await storeError { try await store.save(piece) } == .invalidName(.empty))
            piece.name = String(repeating: "a", count: NameRules.garmentNameMaximum + 1)
            #expect(
                await storeError { try await store.save(piece) }
                    == .invalidName(.tooLong(maximum: NameRules.garmentNameMaximum)))
            #expect(try await store.garment("g-older").name == "Navy trousers")

        case .saveRefusesBadDetails:
            var piece = older
            piece.brand = "Old\nNavy"
            let error = await storeError { try await store.save(piece) }
            guard case .invalidDetails(let problems) = error else {
                Issue.record("Expected invalidDetails, got \(String(describing: error))")
                return
            }
            #expect(problems == GarmentRules.problems(in: piece))
            #expect(try await store.garment("g-older") == older)

        case .updateChangesAndChecks:
            let updated = try await store.update("g-older") { $0.name = " Cream knit " }
            #expect(updated.name == "Cream knit")
            #expect(try await store.garment("g-older") == updated)
            #expect(await storeError { try await store.update("g-older") { $0.name = "" } } == .invalidName(.empty))
            #expect(try await store.garment("g-older").name == "Cream knit")
            #expect(await storeError { try await store.update("nope") { $0.name = "x" } } == .notFound)

        case .wearIsOncePerDayAndLeavesLaundry:
            try await store.setLaundry(.dirty, for: ["g-older"])
            let morning = TestTime.now
            let evening = morning.addingTimeInterval(4 * 3600)
            try await store.recordWear(of: ["g-older", "g-newer"], on: morning)
            try await store.recordWear(of: ["g-older"], on: evening)
            #expect(try await store.garment("g-older").wornOn.count == 1)
            #expect(try await store.garment("g-newer").wornOn.count == 1)
            #expect(try await store.garment("g-older").laundry == .dirty)
            try await store.removeWear(of: ["g-older"], on: evening)
            #expect(try await store.garment("g-older").wornOn.isEmpty)
            #expect(try await store.garment("g-newer").wornOn.allSatisfy { calendar.isDate($0, inSameDayAs: morning) })

        case .wearChangesAllOrNone:
            #expect(
                await storeError { try await store.recordWear(of: ["g-older", "nope"], on: TestTime.now) } == .notFound)
            #expect(try await store.garment("g-older").wornOn.isEmpty)

        case .setsLaundry:
            try await store.setLaundry(.dirty, for: ["g-older", "g-newer"])
            #expect(try await store.garments().allSatisfy { $0.laundry == .dirty })
            try await store.setLaundry(.clean, for: ["g-newer"])
            #expect(try await store.garment("g-newer").laundry == .clean)
            #expect(await storeError { try await store.setLaundry(.clean, for: ["nope"]) } == .notFound)

        case .deleteAndRestore:
            try await store.delete("g-older", at: TestTime.now)
            let deleted = try await store.garment("g-older")
            #expect(deleted.deletedAt == TestTime.now)
            // Recently deleted pieces are still listed; screens filter them.
            #expect(try await store.garments().count == 2)
            try await store.restore("g-older")
            #expect(try await store.garment("g-older").deletedAt == nil)
            #expect(await storeError { try await store.delete("nope", at: TestTime.now) } == .notFound)
            #expect(await storeError { try await store.restore("nope") } == .notFound)

        case .purgesOnlyExpiredPieces:
            try await store.delete("g-older", at: TestTime.day(-31))
            try await store.delete("g-newer", at: TestTime.day(-2))
            #expect(try await store.purgeExpired(asOf: TestTime.now) == ["g-older"])
            #expect(await storeError { try await store.garment("g-older") } == .notFound)
            #expect(try await store.garment("g-newer").isDeleted)
            #expect(try await store.purgeExpired(asOf: TestTime.now).isEmpty)

        case .eraseAllEmptiesIt:
            try await store.delete("g-older", at: TestTime.now)
            try await store.eraseAll()
            #expect(try await store.garments().isEmpty)
            try await store.eraseAll()
        }
    }
}
