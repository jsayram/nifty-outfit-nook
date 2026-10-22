import Foundation
import Models
import NookTestSupport
import Testing

@testable import Fixtures

/// The data every Phase 32a scale check uses must itself be valid, or a store or a restore would
/// refuse it and the check would measure the refusal.
struct ScaleDataTests {
    private static let data = ScaleData.make(
        growing: FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar).garments, now: TestTime.now)

    @Test func everyGarmentAndLookPassesTheStoreChecks() {
        var problems: [String] = []
        for garment in Self.data.garments {
            do {
                _ = try StoreValidation.garment(garment)
            } catch {
                if problems.count < 5 {
                    problems.append("\(garment.id.rawValue) \(garment.name) \(garment.otherNames): \(error)")
                }
            }
        }
        for look in Self.data.looks {
            do {
                _ = try StoreValidation.look(look)
            } catch {
                if problems.count < 5 { problems.append("\(look.id.rawValue): \(error)") }
            }
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func idsAreUnique() {
        #expect(Set(Self.data.garments.map(\.id)).count == Self.data.garments.count)
        #expect(Set(Self.data.looks.map(\.id)).count == Self.data.looks.count)
        #expect(Set(Self.data.pictures.map(\.id)).count == Self.data.pictures.count)
    }
}
