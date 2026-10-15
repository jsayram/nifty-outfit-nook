import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Saved Looks and Make your own look on iPad (Phase 15b), compared with the PNGs in
/// `__Snapshots__/SavedLooksIPadSnapshotTests`.
///
/// Each picture is one 11-inch window (`SnapshotWindow`), laid out as `SavedLooksScreen` lays it
/// out for that width (`BrowseColumns`), drawn at 1x from the top:
/// - the Interview look beside the grid: sideways with the sidebar, upright beside the page,
///   a narrow window (the phone page), sideways in dark, and at AX3 upright (the phone page);
/// - nothing picked yet;
/// - the Pictures tab with the Lace date night picture beside it, sideways and upright;
/// - Make your own look sideways, upright and in a narrow window.
@MainActor
@Suite
struct SavedLooksIPadSnapshotTests {
    // MARK: Looks

    @Test(arguments: SnapshotWindow.allCases)
    func lookBesideTheGrid(window: SnapshotWindow) async {
        await assertColumns(.look("o-interview"), in: window, named: window.rawValue)
    }

    @Test func lookBesideTheGridDark() async {
        await assertColumns(.look("o-interview"), in: .landscape, colorScheme: .dark, named: "dark")
    }

    /// At the accessibility sizes even a wide window keeps the one-column page.
    @Test func largeText() async {
        await assertColumns(.look("o-interview"), in: .portrait, dynamicTypeSize: .accessibility3, named: "ax3")
    }

    @Test func nothingPicked() async {
        await assertColumns(nil, in: .landscape, named: "landscape")
    }

    // MARK: Pictures

    @Test(arguments: [SnapshotWindow.landscape, .portrait])
    func pictureBesideTheGrid(window: SnapshotWindow) async {
        await assertColumns(.picture("p-lace"), tab: .pictures, in: window, named: window.rawValue)
    }

    // MARK: Make your own look

    @Test(arguments: SnapshotWindow.allCases)
    func makeYourOwnLook(window: SnapshotWindow) async {
        let model = await loadedBuilder(startingWith: "g-navy-trousers")
        model.add("g-pink-blouse")
        model.add("g-nude-flats")
        model.name = "Friday pink"
        assertWindowSnapshot(LookBuilderPage(model: model), in: window, named: window.rawValue)
    }

    // MARK: Helpers

    /// The page and what's beside it, as the screen draws them for the window.
    private func assertColumns(
        _ selection: SavedLooksSelection?,
        tab: SavedLooksModel.Tab = .looks,
        in window: SnapshotWindow,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let layout = WindowLayout.browse(
            width: window.size.width, horizontalSizeClass: window.sizeClass, dynamicTypeSize: dynamicTypeSize)
        let model = await loadedSavedLooks()
        model.tab = tab
        let beside = layout.showsDetailBeside ? selection : nil
        let services = FixtureServices.make(set: .demo, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        var look: LookDetailModel?
        var picture: PictureDetailModel?
        switch beside {
        case .look(let id):
            let detail = LookDetailModel(lookID: id, now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar)
            await detail.load(from: services)
            look = detail
        case .picture(let id):
            let detail = PictureDetailModel(
                pictureID: id, now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar)
            await detail.load(from: services)
            picture = detail
        case nil:
            break
        }
        let view = BrowseColumns(layout: layout, width: window.size.width, identifier: "savedLooks") { part in
            SavedLooksPage(model: model, part: part, current: beside, opensBeside: layout.showsDetailBeside)
        } detail: {
            if let look {
                LookDetailPage(model: look)
            } else if let picture {
                PictureDetailPage(model: picture)
            } else {
                BrowseDetailPlaceholder(
                    title: SavedLooksText.pickLookTitle, message: SavedLooksText.pickLookMessage,
                    systemImage: "bookmark")
            }
        }
        assertWindowSnapshot(
            view, in: window, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, named: name,
            fileID: fileID, filePath: filePath, testName: testName, line: line, column: column)
    }
}
