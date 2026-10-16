import DesignSystem
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import Features

/// Home's large-text and sideways layouts (Phase 5b), compared with the PNGs in
/// `__Snapshots__/HomeLayoutSnapshotTests`.
///
/// The large-text page is drawn 402 points wide (iPhone 17) at AX3 in light and at AX5, the
/// largest size, in dark, at its full height, as if scrolled. The sideways room is drawn at
/// iPhone 17's 874 x 402 with the safe area measured there on iOS 26.5 (62 points at each side,
/// 64 for the tab bar), in light and at night in dark. The system bars aren't in the pictures.
@MainActor
@Suite(.heavyMainActorWork)
struct HomeLayoutSnapshotTests {
    static let demo = HomeSnapshotTests.demo

    /// A snowy night with a full hamper, tracking on, in a suitcase.
    static let night = HomeRoomContent(
        signName: "Lily",
        source: SourcePlate(kind: .suitcase(name: "Jose’s house"), pieceCount: 5),
        hamper: .toWash(8),
        weather: WeatherSnapshot(condition: .snow, temperatureCelsius: -1.1, isNight: true, observedAt: .distantPast)
    )

    static let iPhone17Width: CGFloat = 402
    static let sidewaysSize = CGSize(width: 874, height: 402)
    static let sidewaysInsets = EdgeInsets(top: 0, leading: 62, bottom: 64, trailing: 62)

    @Test func largeTextAX3() {
        let view = HomeLargeTextView(content: Self.demo, open: { _ in }, notice: { EmptyView() })
        assertLayoutSnapshot(
            view, size: CGSize(width: Self.iPhone17Width, height: 0), colorScheme: .light,
            dynamicTypeSize: .accessibility3, named: "ax3")
    }

    @Test func largeTextAX5Dark() {
        let view = HomeLargeTextView(content: Self.night, open: { _ in }, notice: { EmptyView() })
        assertLayoutSnapshot(
            view, size: CGSize(width: Self.iPhone17Width, height: 0), colorScheme: .dark,
            dynamicTypeSize: .accessibility5, named: "ax5-dark")
    }

    @Test func sideways() {
        let view = HomeSidewaysView(
            content: Self.demo, open: { _ in }, openProfile: {}, screenInsets: Self.sidewaysInsets,
            notice: { EmptyView() })
        assertLayoutSnapshot(
            view, size: Self.sidewaysSize, colorScheme: .light, dynamicTypeSize: .large, named: "sideways")
    }

    @Test func sidewaysDarkNight() {
        let view = HomeSidewaysView(
            content: Self.night, open: { _ in }, openProfile: {}, screenInsets: Self.sidewaysInsets,
            notice: { EmptyView() })
        assertLayoutSnapshot(
            view, size: Self.sidewaysSize, colorScheme: .dark, dynamicTypeSize: .large, named: "sideways-dark-night")
    }

    /// A height of 0 means "as tall as it needs".
    private func assertLayoutSnapshot(
        _ view: some View,
        size: CGSize,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let height: CGFloat? = size.height > 0 ? size.height : nil
        let content =
            view
            .frame(width: size.width, height: height)
            .fixedSize(horizontal: false, vertical: height == nil)
            .background(Color.nook.background)
            .environment(\.roomIsStillImage, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width, height: height)
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
