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

/// Profile and its screens on iPad (Phase 15b), compared with the PNGs in
/// `__Snapshots__/ProfileIPadSnapshotTests`.
///
/// Each picture is one 11-inch window (`SnapshotWindow`), drawn at 1x from the top. The wall runs
/// the full width and the title, the drawing and the rows keep to one readable column in the
/// middle: Profile sideways, upright and in a narrow window; Fit and measurements, Help and
/// Privacy and terms sideways.
@MainActor
@Suite(.heavyMainActorWork)
struct ProfileIPadSnapshotTests {
    private func model() -> ProfileModel {
        let profile = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar).profile
        let model = ProfileModel()
        model.show(profile, locale: Locale(identifier: "en_US"))
        return model
    }

    @Test(arguments: SnapshotWindow.allCases)
    func profile(window: SnapshotWindow) {
        assertWindowSnapshot(ProfilePage(model: model()), in: window, backdrop: .floor, named: window.rawValue)
    }

    @Test func fit() {
        assertWindowSnapshot(FitPage(model: model()), in: .landscape, backdrop: .floor, named: "landscape")
    }

    @Test func help() {
        let page = HelpPage(open: [HelpContent.topics[0].id], version: AppVersion(version: "0.1", build: "1"))
        assertWindowSnapshot(page, in: .landscape, backdrop: .floor, named: "landscape")
    }

    @Test func privacy() {
        assertWindowSnapshot(PrivacyPage(), in: .landscape, backdrop: .floor, named: "landscape")
    }
}
