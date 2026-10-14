import Foundation
import Models
import Testing

@testable import Fixtures

/// The large closet must stay quick to build, filter and style (Definition of done, item 7;
/// RD-13.1, LR-07.5, LR-09.4).
///
/// The bounds are loose on purpose. Tests run as a Debug build on a simulator, and CI runners
/// are slower than a dev Mac, so each bound sits well above what we measured locally (see
/// docs/models.md). A failure means something got many times slower, not a little.
struct LargeClosetPerformanceTests {
    private static let data = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)

    private func time(_ work: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try work()
        return clock.now - start
    }

    @Test func generatingTheLargeClosetIsFast() {
        let elapsed = time { _ = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar) }
        #expect(elapsed < .seconds(1), "Generating took \(elapsed)")
    }

    @Test func filteringTheLargeClosetIsFast() {
        let garments = Self.data.garments
        let suitcases = Self.data.suitcases
        let filters = [
            GarmentFilter(categories: [.top]),
            GarmentFilter(categories: [.bottom], colors: [.black, .navy]),
            GarmentFilter(packing: .inASuitcase),
            GarmentFilter(query: "beach"),
            GarmentFilter(categories: [.shoes], colors: [.tan], packing: .notPacked, query: "soft"),
        ]
        var matched = 0
        let elapsed = time {
            let inCloset = garments.filter(\.isInCloset)
            for filter in filters { matched += filter.apply(to: inCloset, suitcases: suitcases).count }
        }
        #expect(matched > 0)
        #expect(elapsed < .milliseconds(500), "Five filters took \(elapsed)")
    }

    @Test func buildingAContextAndStylingIsFast() async throws {
        let request = makeRequest()
        var context: StylingContext?
        let built = try time {
            context = try StylingContext.from(Self.data, request: request)
        }
        #expect(built < .milliseconds(500), "Building the context took \(built)")

        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await MockStylist().style(try #require(context))
        let styled = clock.now - start
        #expect(outcome.result != nil)
        #expect(styled < .milliseconds(500), "Styling took \(styled)")
    }

    @Test(arguments: Occasion.allCases)
    func everyResultFromTheLargeClosetPassesTheCheck(occasion: Occasion) async throws {
        let sources: [WardrobeSource] =
            [.mainCloset] + Self.data.suitcases.filter { !$0.isArchived }.prefix(5).map { .suitcase($0.id) }
        for source in sources {
            for mode in PieceMode.allCases {
                let request = makeRequest(source: source, occasion: occasion, pieceMode: mode, tracksLaundry: true)
                let context = try StylingContext.from(Self.data, request: request)
                let outcome = try await MockStylist().style(context)
                if let result = outcome.result {
                    #expect(ResultCheck.problems(in: result, for: context).isEmpty, "\(occasion) \(source) \(mode)")
                }
            }
        }
    }
}
