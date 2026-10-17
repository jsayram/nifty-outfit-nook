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

/// Closet's page (Phase 6), compared with the PNGs in `__Snapshots__/ClosetSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at its full height, as if scrolled, without the navigation
/// and tab bars: the demo closet with laundry tracking on (Dirty badges and the Laundry tile), the
/// same in dark, at AX5 (filters folded away, one piece per row), with no matches, empty, and
/// failed to load. Plus the Suitcases and Laundry tiles alone on a 375 point iPhone SE.
@MainActor
@Suite(.heavyMainActorWork)
struct ClosetSnapshotTests {
    static let width: CGFloat = 402

    private func model(_ set: FixtureSet, laundry: FixtureLaundryState? = nil) -> ClosetModel {
        var data = set.data(now: TestTime.now, calendar: TestTime.calendar)
        if laundry != nil {
            // The same as `-fixtures demo:laundry=some`: tracking on, two pieces in the wash.
            data.profile.preferences.tracksLaundry = true
        }
        // Newest first, as the store hands them over.
        let garments = data.garments.sorted { $0.addedAt > $1.addedAt }
        let model = ClosetModel()
        model.show(garments, suitcases: data.suitcases, profile: data.profile, now: TestTime.now)
        return model
    }

    @Test func demoCloset() {
        assertPageSnapshot(model(.demo, laundry: .some), named: "demo")
    }

    @Test func demoClosetDark() {
        assertPageSnapshot(model(.demo, laundry: .some), colorScheme: .dark, named: "demo-dark")
    }

    @Test func demoClosetAX5() {
        assertPageSnapshot(model(.demo), dynamicTypeSize: .accessibility5, named: "ax5")
    }

    /// On a 375 point iPhone SE the Suitcases and Laundry tiles stack, so "Suitcases" keeps its
    /// line instead of breaking as "Suitcas-es" (QA, October 2026). Only the tiles are drawn.
    @Test func tilesOnIPhoneSE() {
        let tiles = ClosetTiles(suitcaseCount: 5, tracksLaundry: true, dirtyCount: 2, open: { _ in })
            .padding(NookSpacing.screenMargin)
            .background(Color.nook.floor)
        let content =
            tiles
            .frame(width: 375)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, TestTime.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 375, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image")
            return
        }
        SnapshotTesting.assertSnapshot(
            of: image, as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: 1), named: "tiles-se")
        // Side by side on the iPhone 17, one above the other on the SE.
        let single = ClosetTiles(suitcaseCount: 5, tracksLaundry: false, dirtyCount: 0, open: { _ in })
        let oneHigh = fittedHeight(of: single, width: 370)
        let both = ClosetTiles(suitcaseCount: 5, tracksLaundry: true, dirtyCount: 2, open: { _ in })
        #expect(fittedHeight(of: both, width: 370) < oneHigh * 1.5)
        #expect(fittedHeight(of: both, width: 343) > oneHigh * 1.5)
    }

    @Test func noMatches() {
        let model = model(.demo)
        model.toggle(.shoes)
        model.toggle(.pink)
        assertPageSnapshot(model, named: "no-matches")
    }

    @Test func emptyCloset() {
        assertPageSnapshot(model(.empty), named: "empty")
    }

    @Test func failedToLoad() async {
        let model = ClosetModel()
        let services = FixtureServices.make(
            set: .demo, behavior: .storesFail, now: TestTime.now, calendar: TestTime.calendar)
        await model.load(from: services, now: TestTime.now)
        assertPageSnapshot(model, named: "failed")
    }

    private func assertPageSnapshot(
        _ model: ClosetModel,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let page = ClosetPage(model: model, open: { _ in }, retry: {})
        expectFitsWidth(
            page, width: Self.width, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, named: name,
            fileID: fileID, filePath: filePath, line: line, column: column)
        let content =
            page
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, TestTime.locale)
            .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        assertSnapshot(
            of: image,
            as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: 1),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
