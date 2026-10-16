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

/// Your looks (Phase 10b), compared with the PNGs in `__Snapshots__/YourLooksSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars, from
/// the demo closet on a rainy Office day:
/// - each version: Simple, Dressed up and Something new with its idea piece;
/// - Something new from a suitcase (owned only, with the note) and with Only mine;
/// - each state: styling, partial (Jose's house), insufficient (Gym), didn't finish, offline,
///   stopped, and offline after Try a different outfit with the looks kept;
/// - the Saved tab with looks and empty;
/// - Simple and the styling state at AX5; Something new, offline and Saved in dark.
@MainActor
@Suite(.heavyMainActorWork)
struct YourLooksSnapshotTests {
    static let width: CGFloat = 402

    // MARK: Versions

    @Test func simple() async {
        assertSnapshot(YourLooksPage(model: await styledLooks()), named: "simple")
    }

    @Test func dressedUp() async {
        let model = await styledLooks()
        model.version = .dressedUp
        assertSnapshot(YourLooksPage(model: model), named: "dressed-up")
    }

    @Test func somethingNew() async {
        let model = await styledLooks()
        model.version = .somethingNew
        assertSnapshot(YourLooksPage(model: model), named: "something-new")
    }

    @Test func somethingNewDark() async {
        let model = await styledLooks()
        model.version = .somethingNew
        assertSnapshot(YourLooksPage(model: model), colorScheme: .dark, named: "something-new-dark")
    }

    /// LR-05b.2: from a suitcase, Something new stays owned and says why.
    @Test func somethingNewFromASuitcase() async {
        let model = await styledLooks(lookRequest(source: .suitcase("s-weekend"), occasion: .casual))
        model.version = .somethingNew
        assertSnapshot(YourLooksPage(model: model), named: "something-new-suitcase")
    }

    @Test func simpleAX5() async {
        assertSnapshot(
            YourLooksPage(model: await styledLooks()), dynamicTypeSize: .accessibility5, scale: 1, named: "simple-ax5")
    }

    // MARK: States

    @Test func styling() async throws {
        let model = try await stylingModel()
        assertSnapshot(YourLooksPage(model: model), named: "styling")
        model.cancel()
    }

    @Test func stylingAX5() async throws {
        let model = try await stylingModel()
        assertSnapshot(YourLooksPage(model: model), dynamicTypeSize: .accessibility5, scale: 1, named: "styling-ax5")
        model.cancel()
    }

    /// Jose's house can't make every version.
    @Test func partial() async {
        let model = await styledLooks(lookRequest(source: .suitcase("s-jose")))
        assertSnapshot(YourLooksPage(model: model), named: "partial")
    }

    /// Gym has a tee and sneakers: no bottom.
    @Test func insufficient() async {
        let model = await styledLooks(lookRequest(source: .suitcase("s-gym")))
        assertSnapshot(YourLooksPage(model: model), named: "insufficient")
    }

    @Test func failed() async {
        let model = await styledLooks(services: yourLooksServices(behavior: .stylistFails))
        assertSnapshot(YourLooksPage(model: model), named: "failed")
    }

    @Test func offline() async {
        let model = await styledLooks(services: yourLooksServices(behavior: .offline))
        assertSnapshot(YourLooksPage(model: model), named: "offline")
    }

    @Test func offlineDark() async {
        let model = await styledLooks(services: yourLooksServices(behavior: .offline))
        assertSnapshot(YourLooksPage(model: model), colorScheme: .dark, named: "offline-dark")
    }

    @Test func stopped() async throws {
        let model = try await stylingModel()
        model.cancel()
        assertSnapshot(YourLooksPage(model: model), named: "stopped")
    }

    /// Try a different outfit offline: the looks stay, with the banner and the connection line.
    @Test func offlineWithLooks() async {
        let stylist = ScriptedStylist([.style(.normal), .fail(.offline)])
        let model = await styledLooks(services: yourLooksServices(stylist: stylist))
        model.tryDifferentOutfit()
        await model.settle()
        assertSnapshot(YourLooksPage(model: model), named: "offline-with-looks")
    }

    // MARK: Saved tab

    @Test func savedTab() async {
        let model = await styledLooks()
        model.tab = .saved
        assertSnapshot(YourLooksPage(model: model), named: "saved")
    }

    @Test func savedTabDark() async {
        let model = await styledLooks()
        model.tab = .saved
        assertSnapshot(YourLooksPage(model: model), colorScheme: .dark, named: "saved-dark")
    }

    /// LR-06.2: nothing saved for a concert yet.
    @Test func savedTabEmpty() async {
        let model = await styledLooks(lookRequest(occasion: .concert))
        model.tab = .saved
        assertSnapshot(YourLooksPage(model: model), named: "saved-empty")
    }

    // MARK: Helpers

    /// A model waiting on the stylist, with its pieces checked.
    private func stylingModel() async throws -> YourLooksModel {
        let model = yourLooksModel()
        model.start(with: yourLooksServices(stylist: ScriptedStylist([.wait])))
        do {
            try await waitUntil { model.status == .styling(.choosing) }
        } catch {
            model.cancel()
            throw error
        }
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
            .environment(\.locale, TestTime.locale)
            .environment(\.calendar, TestTime.calendar)
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
