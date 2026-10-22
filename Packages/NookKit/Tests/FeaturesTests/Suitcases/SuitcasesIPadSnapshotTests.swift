import DesignSystem
import Fixtures
import Models
import NookTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Suitcases and Laundry on iPad (Phase 15b), compared with the PNGs in
/// `__Snapshots__/SuitcasesIPadSnapshotTests`.
///
/// Each picture is one 11-inch window (`SnapshotWindow`), drawn at 1x from the top. The wall runs
/// the full width and the title, the drawing and the rows keep to one readable column in the
/// middle: Suitcases sideways, upright and in a narrow window; Jose's house sideways; Laundry
/// with two pieces in the wash sideways and upright.
@MainActor
@Suite(.heavyMainActorWork, .ipadSnapshots)
struct SuitcasesIPadSnapshotTests {
    private let now = TestTime.now

    private func data(tracksLaundry: Bool = false) -> FixtureData {
        var data = FixtureSet.demo.data(now: now, calendar: TestTime.calendar)
        data.profile.remembered.source = .suitcase("s-jose")
        data.profile.preferences.tracksLaundry = tracksLaundry
        data.garments.sort { $0.addedAt > $1.addedAt }
        return data
    }

    @Test(arguments: SnapshotWindow.allCases)
    func suitcases(window: SnapshotWindow) {
        let data = data()
        let model = SuitcasesModel()
        model.show(suitcases: data.suitcases, garments: data.garments, profile: data.profile, now: now)
        assertWindowSnapshot(SuitcasesPage(model: model), in: window, backdrop: .floor, named: window.rawValue)
    }

    @Test func suitcase() {
        let data = data()
        let model = SuitcaseDetailModel(suitcaseID: "s-jose")
        model.show(suitcases: data.suitcases, garments: data.garments, profile: data.profile, now: now)
        assertWindowSnapshot(SuitcaseDetailPage(model: model), in: .landscape, backdrop: .floor, named: "landscape")
    }

    @Test(arguments: [SnapshotWindow.landscape, .portrait])
    func laundry(window: SnapshotWindow) {
        let data = data(tracksLaundry: true)
        let model = LaundryModel()
        model.show(garments: data.garments, suitcases: data.suitcases, profile: data.profile)
        assertWindowSnapshot(LaundryPage(model: model), in: window, backdrop: .floor, named: window.rawValue)
    }
}
