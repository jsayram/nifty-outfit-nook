import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import Features

/// The room on three phone sizes in light appearance, compared with the PNGs in
/// `__Snapshots__/HomeSnapshotTests`. Dark and the large-text layout come with Phase 5b.
///
/// The canvas is drawn the way the screen draws it, between bars of the measured height; the
/// system navigation bar and tab bar themselves aren't in the picture. The iPhone SE room is
/// taller than its screen because it scrolls. How to record new references is in
/// `DesignSystem/README.md` under "Snapshot tests".
@MainActor
@Suite
struct HomeSnapshotTests {
    static let demo = HomeRoomContent(
        signName: "Lily", source: SourcePlate(kind: .mainCloset, pieceCount: 17), hamper: .off)

    @Test(arguments: PhoneScreen.allCases)
    func room(phone: PhoneScreen) {
        assertRoomSnapshot(Self.demo, on: phone, named: phone.rawValue)
    }

    /// A fresh install: no name on the sign, an empty closet.
    @Test func emptyRoom() {
        let empty = HomeRoomContent(signName: "", source: SourcePlate(kind: .mainCloset, pieceCount: 0), hamper: .off)
        assertRoomSnapshot(empty, on: .iPhone17, named: "empty")
    }

    /// A long name wraps and shrinks on the sign; a suitcase source turns its plate green.
    @Test func longNameAndSuitcase() {
        let content = HomeRoomContent(
            signName: "Anna-Katharina Lee",
            source: SourcePlate(kind: .suitcase(name: "Jose’s house"), pieceCount: 5),
            hamper: .toWash(2)
        )
        assertRoomSnapshot(content, on: .iPhoneSE, named: "long-name-suitcase")
    }

    @Test func runsOnTheRecordedRuntime() {
        #expect(
            UIDevice.current.systemVersion == "26.5", "Snapshots were recorded on iOS 26.5. Run them on that simulator."
        )
    }

    private func assertRoomSnapshot(
        _ content: HomeRoomContent,
        on phone: PhoneScreen,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let layout = phone.layout
        let view = RoomCanvas(layout: layout, content: content, open: { _ in })
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: layout.size.width, height: layout.contentHeight)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        assertSnapshot(
            of: image,
            as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: 2),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
