import Foundation
import Models
import Testing

@testable import Fixtures

/// The large closet must stay quick to build, filter and style (Definition of done, item 7;
/// RD-13.1, LR-07.5, LR-09.4).
///
/// The bounds are loose on purpose. Tests run as a Debug build on a simulator, and CI runners
/// are slower than a dev Mac, so each bound sits well above what we measured locally (see
/// docs/models.md). Each check takes the fastest of three runs and allows three times as long on
/// CI (`SpeedCheck`). A failure means something got many times slower, not a little.
struct LargeClosetPerformanceTests {
    private static let data = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)

    @Test func generatingTheLargeClosetIsFast() {
        let elapsed = SpeedCheck.fastest { _ = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar) }
        #expect(elapsed < SpeedCheck.limit(.seconds(1)), "Generating took \(elapsed)")
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
        let elapsed = SpeedCheck.fastest {
            matched = 0
            let inCloset = garments.filter(\.isInCloset)
            for filter in filters { matched += filter.apply(to: inCloset, suitcases: suitcases).count }
        }
        #expect(matched > 0)
        #expect(elapsed < SpeedCheck.limit(.milliseconds(500)), "Five filters took \(elapsed)")
    }

    @Test func buildingAContextAndStylingIsFast() async throws {
        let request = makeRequest()
        var context: StylingContext?
        let built = try SpeedCheck.fastest {
            context = try StylingContext.from(Self.data, request: request)
        }
        #expect(built < SpeedCheck.limit(.milliseconds(500)), "Building the context took \(built)")

        let ready = try #require(context)
        var outcome: StyleOutcome?
        let styled = try await SpeedCheck.fastest {
            outcome = try await MockStylist().style(ready)
        }
        #expect(outcome?.result != nil)
        #expect(styled < SpeedCheck.limit(.milliseconds(500)), "Styling took \(styled)")
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
