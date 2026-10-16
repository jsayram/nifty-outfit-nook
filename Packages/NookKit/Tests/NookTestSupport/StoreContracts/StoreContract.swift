import Foundation
import Models
import Testing

// Store contracts: what every implementation of a store protocol must do, written once and run
// against each store. Stage A runs them on the in-memory stores (FixturesTests) and the app-state
// stores kept in UserDefaults (ServicesTests). Stage B's real stores run the same contracts, so a
// screen can't tell which store is behind the protocol.
//
// Each contract takes a factory that makes a store holding the given records, and lists its
// checks as an enum, so a test target runs every check as its own test case:
//
//     @Test(arguments: ClosetStoreContract.Check.allCases)
//     func closet(_ check: ClosetStoreContract.Check) async throws {
//         try await ClosetStoreContract { InMemoryClosetStore(garments: $0, calendar: $1) }.run(check)
//     }
//
// A check records its failures with `#expect`, and throws only when a store call it relies on
// fails unexpectedly.

/// The records the contracts are built from. Dates are around `TestTime.now`.
enum ContractData {
    static let calendar = TestTime.calendar

    static func garment(
        _ id: Garment.ID, name: String? = nil, category: GarmentCategory = .top, addedDaysAgo: Int = 0
    ) -> Garment {
        Garment(id: id, name: name ?? "Piece \(id)", category: category, addedAt: TestTime.day(-addedDaysAgo))
    }

    static func look(_ id: Look.ID, name: String? = nil, pieces: [Garment.ID] = ["g1"], createdDaysAgo: Int = 0)
        -> Look
    {
        Look(
            id: id,
            pieces: pieces.map { LookPiece(id: LookPiece.ID("\(id)-\($0)"), content: .garment($0)) },
            name: name, isSaved: name != nil, createdAt: TestTime.day(-createdDaysAgo))
    }

    static func suitcase(_ id: Suitcase.ID, name: String, pieces: Set<Garment.ID> = []) -> Suitcase {
        Suitcase(id: id, name: name, garmentIDs: pieces, createdAt: TestTime.day(-10))
    }
}

/// The `StoreError` a call threw, or `nil` when it didn't throw. Any other error is a failure.
func storeError<T>(_ call: () async throws -> T) async -> StoreError? {
    do {
        _ = try await call()
        return nil
    } catch let error as StoreError {
        return error
    } catch {
        Issue.record("Expected a StoreError, got \(error)")
        return nil
    }
}
