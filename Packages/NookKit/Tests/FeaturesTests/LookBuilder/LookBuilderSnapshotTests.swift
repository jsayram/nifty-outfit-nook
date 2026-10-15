import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Make your own look (Phase 11), compared with the PNGs in `__Snapshots__/LookBuilderSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars:
/// - empty, as "+ Make your own" opens it;
/// - from the navy dress pants with a top and shoes added and a name, in light, dark and AX5;
/// - a top and shoes only, saying what's missing;
/// - the draft card after a relaunch;
/// - saved;
/// - the Add a piece picker;
/// - the error state.
@MainActor
@Suite
struct LookBuilderSnapshotTests {
    static let width: CGFloat = 402

    private func built() async -> LookBuilderModel {
        let model = await loadedBuilder(startingWith: "g-navy-trousers")
        model.add("g-pink-blouse")
        model.add("g-nude-flats")
        model.name = "Friday pink"
        return model
    }

    @Test func empty() async {
        assertSnapshot(LookBuilderPage(model: await loadedBuilder()), named: "empty")
    }

    @Test func pieces() async {
        assertSnapshot(LookBuilderPage(model: await built()), named: "pieces")
    }

    @Test func piecesDark() async {
        assertSnapshot(LookBuilderPage(model: await built()), colorScheme: .dark, named: "pieces-dark")
    }

    @Test func piecesAX5() async {
        assertSnapshot(
            LookBuilderPage(model: await built()), dynamicTypeSize: .accessibility5, scale: 1, named: "pieces-ax5")
    }

    @Test func needsABottom() async {
        let model = await loadedBuilder(startingWith: "g-pink-blouse")
        model.add("g-nude-flats")
        assertSnapshot(LookBuilderPage(model: model), named: "needs-a-bottom")
    }

    @Test func draftOffered() async {
        let model = await loadedBuilder(services: builderServices(draft: .look))
        assertSnapshot(LookBuilderPage(model: model), named: "draft")
    }

    @Test func saved() async throws {
        let model = await built()
        try await model.save(fallbackName: "")
        assertSnapshot(LookBuilderPage(model: model), named: "saved")
    }

    @Test func picker() async {
        let model = await loadedBuilder(startingWith: "g-navy-trousers")
        let picker = ClosetModel(scope: model.pickerScope())
        picker.show(
            Array(model.garments.values), suitcases: model.suitcases, profile: Profile(), now: ClosetTestTime.now)
        assertSnapshot(
            NookSheetContainer(title: LookBuilderText.pickerTitle) {
                PiecePicker(
                    model: picker, lead: LookBuilderText.pickerLead, prompt: "Search these pieces", hint: "",
                    emptyTitle: "", emptyMessage: ""
                ) { _ in }
            }
            .background(Color.nook.wallGradient),
            named: "picker")
    }

    @Test func failed() async {
        let model = await loadedBuilder(services: builderServices(behavior: .storesFail))
        assertSnapshot(LookBuilderPage(model: model), named: "failed")
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
