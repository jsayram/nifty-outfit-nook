import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Closet stays quick with the large closet (RD-13.1, LR-09.4, Definition of done item 7).
///
/// Measured serially on an Apple-silicon Mac, iOS 26.5 simulator, Debug: see docs/closet.md.
/// The bounds sit far above those numbers so CI doesn't flake; a failure means something got
/// many times slower.
@MainActor
struct LargeClosetBrowsingTests {
    private static let data = FixtureSet.large.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)

    private func time(_ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        work()
        return clock.now - start
    }

    @Test func preparingTheGridIsFast() {
        let model = ClosetModel()
        let elapsed = time {
            model.show(
                Self.data.garments, suitcases: Self.data.suitcases, profile: Self.data.profile,
                now: ClosetTestTime.now)
        }
        #expect(model.items.count > 2_000)
        #expect(elapsed < .milliseconds(500), "Preparing \(model.items.count) pieces took \(elapsed)")
    }

    @Test func eachFilterAndSearchIsFast() {
        let model = ClosetModel()
        model.show(
            Self.data.garments, suitcases: Self.data.suitcases, profile: Self.data.profile, now: ClosetTestTime.now)
        var slowest = Duration.zero
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
        for step in steps {
            slowest = max(slowest, time { step(model) })
        }
        #expect(model.shown.count == model.items.count)
        #expect(slowest < .milliseconds(150), "The slowest step took \(slowest)")
    }
}
