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

/// Closet on iPad (Phase 15a), compared with the PNGs in `__Snapshots__/ClosetIPadSnapshotTests`.
///
/// Each picture is one window, as `ClosetScreen` lays it out for that width: the sidebar, the
/// grid and the navy trousers beside it on the 11- and 13-inch iPads held sideways (the 13-inch
/// in dark), the page with the detail beside it upright, a window a third of the screen wide
/// (compact, so the phone page), and the page at AX3 on an upright iPad. The columns are drawn
/// from their tops, as if not scrolled, without the system bars. Drawn at 1x, like
/// `HomeIPadSnapshotTests`.
@MainActor
@Suite(.heavyMainActorWork, .ipadSnapshots)
struct ClosetIPadSnapshotTests {
    private static let trousers: Garment.ID = "g-navy-trousers"

    private func closetModel() -> ClosetModel {
        var data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        data.profile.preferences.tracksLaundry = true
        let garments = data.garments.sorted { $0.addedAt > $1.addedAt }
        let model = ClosetModel()
        model.show(garments, suitcases: data.suitcases, profile: data.profile, now: TestTime.now)
        return model
    }

    private func detailModel() throws -> GarmentDetailModel {
        var data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        data.profile.preferences.tracksLaundry = true
        let garment = try #require(data.garments.first { $0.id == Self.trousers })
        let model = GarmentDetailModel(garmentID: Self.trousers)
        model.show(
            garment, suitcases: data.suitcases, looks: data.looks.sorted { $0.createdAt > $1.createdAt },
            profile: data.profile, now: TestTime.now)
        return model
    }

    @Test func sidebarOn11InchSideways() throws {
        try assertWindow(.iPad11Landscape, expected: .sidebar, named: "11-landscape")
    }

    @Test func sidebarOn13InchSidewaysDark() throws {
        try assertWindow(.iPad13Landscape, expected: .sidebar, colorScheme: .dark, named: "13-landscape-dark")
    }

    @Test func detailBesideThePageUpright() throws {
        try assertWindow(.iPad11Portrait, expected: .pageAndDetail, named: "11-portrait")
        // The 13-inch upright has the same layout; its picture added nothing the 11-inch one
        // doesn't show.
        #expect(
            WindowLayout.browse(
                width: IPadWindow.iPad13Portrait.size.width, horizontalSizeClass: .regular,
                dynamicTypeSize: .large) == .pageAndDetail)
    }

    /// Nothing picked yet: the quiet note beside the grid.
    @Test func nothingPicked() throws {
        try assertWindow(.iPad11Landscape, expected: .sidebar, picksPiece: false, named: "nothing-picked")
    }

    /// A third of the 11-inch screen held sideways: compact width, the phone page.
    @Test func compactWindow() throws {
        try assertWindow(
            size: CGSize(width: 416, height: 834), sizeClass: .compact, expected: .stack, named: "compact-third")
    }

    /// At the accessibility sizes even a wide window keeps the one-column page.
    @Test func largeTextOnIPad() throws {
        try assertWindow(.iPad11Portrait, expected: .stack, dynamicTypeSize: .accessibility3, named: "ax3")
    }

    private func assertWindow(
        _ window: IPadWindow,
        expected: BrowseLayout,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        picksPiece: Bool = true,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        try assertWindow(
            size: window.size, sizeClass: .regular, expected: expected, colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize, picksPiece: picksPiece, named: name, fileID: fileID,
            filePath: filePath, testName: testName, line: line, column: column)
    }

    private func assertWindow(
        size: CGSize,
        sizeClass: UserInterfaceSizeClass,
        expected: BrowseLayout,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        picksPiece: Bool = true,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let layout = WindowLayout.browse(
            width: size.width, horizontalSizeClass: sizeClass, dynamicTypeSize: dynamicTypeSize)
        #expect(layout == expected, "\(name) got \(layout)")
        let model = closetModel()
        let detail = try detailModel()
        let current = picksPiece && layout.showsDetailBeside ? Self.trousers : nil
        let view = BrowseColumns(layout: layout, width: size.width, identifier: "closet") { part in
            ClosetPage(
                model: model, open: { _ in }, retry: {}, part: part, current: current,
                opensBeside: layout.showsDetailBeside)
        } detail: {
            if current != nil {
                GarmentDetailPage(model: detail, actions: GarmentDetailActions(edit: {}))
            } else {
                ClosetDetailPlaceholder()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .background(Color.nook.floor)
        .environment(\.closetIsStillImage, true)
        .environment(\.nookStaticRendering, true)
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, TestTime.locale)
        .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: view.snapshotPhotos())
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
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
