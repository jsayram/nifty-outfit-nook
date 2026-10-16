import DesignSystem
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import Features

/// Home on iPad (Phase 15a), compared with the PNGs in `__Snapshots__/HomeIPadSnapshotTests`:
/// the tall room on the 11-inch iPad upright, the wide room held sideways on both sizes, the wide
/// room in dark, a window a third of the screen wide (compact, so the phone room), and the
/// large-text page at AX5 on an upright iPad.
///
/// The canvas is the whole window, with the bars measured on the iOS 26.5 simulator (86 points
/// at the top, 77 for the tab bar); the system bars themselves aren't in the pictures. These
/// are drawn at 1x, like every screen snapshot: a 2x picture of a 13-inch screen is several
/// megabytes and 1x still catches a moved drawing or a changed plate.
@MainActor
@Suite(.heavyMainActorWork)
struct HomeIPadSnapshotTests {
    static let demo = HomeSnapshotTests.demo

    @Test(arguments: [
        IPadWindow.iPad11Portrait, .iPad11Landscape, .iPad13Landscape,
    ])
    func room(window: IPadWindow) {
        assertRoomSnapshot(window.roomLayout, named: window.rawValue)
    }

    @Test func wideRoomDark() {
        assertRoomSnapshot(IPadWindow.iPad11Landscape.roomLayout, colorScheme: .dark, named: "dark")
    }

    /// A Split View or Stage Manager window a third of the 11-inch screen held sideways is
    /// compact width (measured: 416 x 834), so it gets the phone room.
    @Test func compactWindow() {
        let layout = WindowLayout.room(
            size: CGSize(width: 416, height: 834), insets: IPadWindow.bars, horizontalSizeClass: .compact)
        #expect(layout.plan.kind == .upright)
        assertRoomSnapshot(layout, named: "compact-third")
    }

    /// At the accessibility sizes an iPad gets the large-text page too, kept to 640 points and
    /// centred.
    @Test func largeTextOnIPad() {
        let size = IPadWindow.iPad11Portrait.size
        let view = HomeLargeTextView(content: Self.demo, open: { _ in }, notice: { EmptyView() })
            .frame(width: size.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.nook.background)
            .environment(\.roomIsStillImage, true)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "en_US"))
        assertImage(view, size: CGSize(width: size.width, height: 0), named: "ax5")
    }

    private func assertRoomSnapshot(
        _ layout: RoomLayout,
        colorScheme: ColorScheme = .light,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let view = RoomCanvas(layout: layout, content: Self.demo, open: { _ in })
            .environment(\.roomIsStillImage, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "en_US"))
        assertImage(
            view, size: CGSize(width: layout.size.width, height: layout.contentHeight), named: name, fileID: fileID,
            filePath: filePath, testName: testName, line: line, column: column)
    }

    /// A height of 0 means "as tall as it needs".
    private func assertImage(
        _ view: some View,
        size: CGSize,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height > 0 ? size.height : nil)
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
