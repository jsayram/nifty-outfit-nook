import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Closet stays quick with the large closet (RD-13.1, LR-09.4, Definition of done item 7).
///
/// Measured serially on an Apple-silicon Mac, iOS 26.5 simulator, Debug: see docs/closet.md.
/// The bounds sit far above those numbers so CI doesn't flake: each check takes the fastest of
/// three runs and allows three times as long on CI (`SpeedCheck`). A failure means something got
/// many times slower.
@MainActor
struct LargeClosetBrowsingTests {
    private static let data = FixtureSet.large.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)

    private func loadedModel() -> ClosetModel {
        let model = ClosetModel()
        model.show(
            Self.data.garments, suitcases: Self.data.suitcases, profile: Self.data.profile, now: ClosetTestTime.now)
        return model
    }

    @Test func preparingTheGridIsFast() {
        var model = ClosetModel()
        let elapsed = SpeedCheck.fastest {
            model = loadedModel()
        }
        #expect(model.items.count > 2_000)
        #expect(
            elapsed < SpeedCheck.limit(.milliseconds(500)), "Preparing \(model.items.count) pieces took \(elapsed)")
    }

    /// Each step changes the filters, so a round runs them all in order on a fresh model, and a
    /// step's time is its fastest over three rounds.
    @Test func eachFilterAndSearchIsFast() {
        let steps: [(ClosetModel) -> Void] = [
            { $0.toggle(.top) },
            { $0.toggle(.navy) },
            { $0.setPacking(.inASuitcase) },
            { $0.toggleDirty() },
            {
                $0.searchText = "soft"
                $0.applySearchNow()
            },
            {
                $0.searchText = "beach house"
                $0.applySearchNow()
            },
            { $0.clearFilters() },
        ]
        var fastest = Array(repeating: Duration.seconds(Int64.max), count: steps.count)
        let clock = ContinuousClock()
        for _ in 0..<3 {
            let model = loadedModel()
            for (index, step) in steps.enumerated() {
                let start = clock.now
                step(model)
                fastest[index] = min(fastest[index], clock.now - start)
            }
            #expect(model.shown.count == model.items.count)
        }
        let slowest = fastest.max() ?? .zero
        #expect(slowest < SpeedCheck.limit(.milliseconds(150)), "The slowest step took \(slowest)")
    }
}
