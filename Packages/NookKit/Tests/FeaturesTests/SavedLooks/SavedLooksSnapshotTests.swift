import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Saved Looks and look detail (Phase 12a), compared with the PNGs in
/// `__Snapshots__/SavedLooksSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars, from
/// the demo closet:
/// - the grid in light, dark and AX5, filtered to black bottoms, with no matches, empty, and the
///   Pictures tab's stand-in;
/// - look detail for the Interview look (light, dark, AX5) and for the Gray blazer office look,
///   whose blazer she gave away (faded, with Swap it).
@MainActor
@Suite
struct SavedLooksSnapshotTests {
    static let width: CGFloat = 402

    // MARK: Grid

    @Test func grid() async {
        assertSnapshot(SavedLooksPage(model: await loadedSavedLooks()), named: "grid")
    }

    @Test func gridDark() async {
        assertSnapshot(SavedLooksPage(model: await loadedSavedLooks()), colorScheme: .dark, named: "grid-dark")
    }

    @Test func gridAX5() async {
        assertSnapshot(
            SavedLooksPage(model: await loadedSavedLooks()), dynamicTypeSize: .accessibility5, scale: 1,
            named: "grid-ax5")
    }

    /// LR-09: Bottoms and Black, the count line and Clear.
    @Test func filtered() async {
        let model = await loadedSavedLooks()
        model.toggle(.bottom)
        model.toggle(.black)
        assertSnapshot(SavedLooksPage(model: model), named: "filtered")
    }

    /// LR-09.3: nothing matches, the filters named, Clear filters.
    @Test func noMatches() async {
        let model = await loadedSavedLooks()
        model.toggle(.dress)
        assertSnapshot(SavedLooksPage(model: model), named: "no-matches")
    }

    /// RD-08.4: nothing saved yet.
    @Test func empty() async {
        assertSnapshot(SavedLooksPage(model: await loadedSavedLooks(.empty)), named: "empty")
    }

    @Test func pictures() async {
        let model = await loadedSavedLooks()
        model.tab = .pictures
        assertSnapshot(SavedLooksPage(model: model), named: "pictures")
    }

    // MARK: Look detail

    @Test func detail() async {
        assertSnapshot(LookDetailPage(model: await detail("o-interview")), named: "detail")
    }

    @Test func detailDark() async {
        assertSnapshot(LookDetailPage(model: await detail("o-interview")), colorScheme: .dark, named: "detail-dark")
    }

    @Test func detailAX5() async {
        assertSnapshot(
            LookDetailPage(model: await detail("o-interview")), dynamicTypeSize: .accessibility5, scale: 1,
            named: "detail-ax5")
    }

    /// LR-16.4: the given-away blazer, faded, with Swap it and the note.
    @Test func detailWithARemovedPiece() async {
        assertSnapshot(LookDetailPage(model: await detail("o-blazer-office")), named: "detail-removed-piece")
    }

    // MARK: Helpers

    private func detail(_ id: Look.ID) async -> LookDetailModel {
        let services = FixtureServices.make(set: .demo, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        let model = LookDetailModel(lookID: id, now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar)
        await model.load(from: services)
        return model
    }

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        scale: CGFloat = 2,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let content =
            view
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, scale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, ClosetTestTime.locale)
            .environment(\.calendar, ClosetTestTime.calendar)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        SnapshotTesting.assertSnapshot(
            of: image,
            as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: scale),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
