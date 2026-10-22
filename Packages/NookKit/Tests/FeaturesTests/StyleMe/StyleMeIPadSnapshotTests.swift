import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Style Me, Your looks and Swap a piece on iPad (Phase 15b), compared with the PNGs in
/// `__Snapshots__/StyleMeIPadSnapshotTests`.
///
/// Each picture is one 11-inch window (`SnapshotWindow`), drawn at 1x from the top:
/// - Your looks sideways and upright, the look beside its pieces and buttons; a narrow window
///   (the phone column); sideways in dark; at AX3 upright, one readable column;
/// - the Saved tab filling the width;
/// - Style Me sideways and upright, the request beside the options, and a narrow window;
/// - Swap a piece sideways and upright, the look beside the options.
@MainActor
@Suite(.heavyMainActorWork, .ipadSnapshots)
struct StyleMeIPadSnapshotTests {
    // MARK: Your looks

    @Test(arguments: SnapshotWindow.allCases)
    func yourLooks(window: SnapshotWindow) async {
        assertWindowSnapshot(YourLooksPage(model: await styledLooks()), in: window, named: window.rawValue)
    }

    @Test func yourLooksDark() async {
        let model = await styledLooks()
        model.version = .somethingNew
        assertWindowSnapshot(YourLooksPage(model: model), in: .landscape, colorScheme: .dark, named: "dark")
    }

    /// At the accessibility sizes the panes stack in one readable column, even on a wide window.
    @Test func yourLooksAX3() async {
        assertWindowSnapshot(
            YourLooksPage(model: await styledLooks()), in: .portrait, dynamicTypeSize: .accessibility3, named: "ax3")
    }

    @Test func savedTab() async {
        let model = await styledLooks()
        model.tab = .saved
        assertWindowSnapshot(YourLooksPage(model: model), in: .landscape, named: "landscape")
    }

    // MARK: Style Me

    @Test(arguments: SnapshotWindow.allCases)
    func styleMe(window: SnapshotWindow) async {
        assertWindowSnapshot(StyleMePage(model: await loadedStyleMe()), in: window, named: window.rawValue)
    }

    // MARK: Swap a piece

    @Test(arguments: [SnapshotWindow.landscape, .portrait])
    func swap(window: SnapshotWindow) async throws {
        let looks = await swappableLooks()
        let model = try #require(looks.swapModel(sourceName: "Main closet"))
        assertWindowSnapshot(SwapPage(model: model), in: window, named: window.rawValue)
    }
}
