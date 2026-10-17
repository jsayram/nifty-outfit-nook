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

/// Add a piece and Edit (Phase 7b), compared with the PNGs in
/// `__Snapshots__/GarmentEditorSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars:
/// - "How would you like to add it?";
/// - Describe in words with suggestions, one accepted and one skipped;
/// - the empty form, the form with the problems Save found, and the cardigan filled in;
/// - the filled form at AX5 and in dark;
/// - "Continue where you left off?".
@MainActor
@Suite(.heavyMainActorWork)
struct GarmentEditorSnapshotTests {
    static let width: CGFloat = 402

    private func filledModel() async -> GarmentEditorModel {
        await loadedEditor(resumesDraft: true, services: editorServices(draft: .add))
    }

    @Test func choices() async {
        let model = await loadedEditor(services: editorServices())
        assertSnapshot(GarmentEditorPage(model: model), named: "choose")
    }

    @Test func describeInWords() async {
        let services = editorServices()
        let model = await loadedEditor(firstStep: .words, services: services)
        model.description = FixtureDrafts.addDescription
        await model.suggest(using: services.descriptions)
        model.decide(.accepted, for: 0)
        model.decide(.skipped, for: 4)
        assertSnapshot(GarmentEditorPage(model: model), named: "words")
    }

    @Test func emptyForm() async {
        let model = await loadedEditor(firstStep: .words, services: editorServices())
        model.continueFromWords()
        assertSnapshot(GarmentEditorPage(model: model), named: "empty-form")
    }

    @Test func formWithProblems() async {
        let services = editorServices()
        let model = await loadedEditor(firstStep: .words, services: services)
        model.continueFromWords()
        model.details.brand = String(repeating: "b", count: 41)
        _ = await model.save(in: services.closet)
        assertSnapshot(GarmentEditorPage(model: model), named: "problems")
    }

    @Test func filledForm() async {
        assertSnapshot(GarmentEditorPage(model: await filledModel()), named: "filled")
    }

    @Test func filledFormAX5() async {
        assertSnapshot(
            GarmentEditorPage(model: await filledModel()), dynamicTypeSize: .accessibility5,
            named: "filled-ax5")
    }

    @Test func filledFormDark() async {
        assertSnapshot(GarmentEditorPage(model: await filledModel()), colorScheme: .dark, named: "filled-dark")
    }

    @Test func continueWhereYouLeftOff() async {
        let model = await loadedEditor(services: editorServices(draft: .add))
        assertSnapshot(GarmentEditorPage(model: model, now: TestTime.now), named: "resume")
    }

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        scale: CGFloat = 1,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        expectFitsWidth(
            view, width: Self.width, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, named: name,
            fileID: fileID, filePath: filePath, line: line, column: column)
        let content =
            view
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, TestTime.locale)
            .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: content.snapshotPhotos())
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
