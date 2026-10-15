import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// The Style Me request (Phase 10a), its sheets and the stand-in results, compared with the PNGs
/// in `__Snapshots__/StyleMeSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars:
/// - the default request (demo closet, 58° and rain), in light, dark and at AX5;
/// - every choice set, from a garment's Style with this;
/// - the states: an empty closet, an empty suitcase, a small suitcase with a starting piece
///   outside it and a required colour it doesn't have, weather that can't be read, and the
///   error state;
/// - each sheet: Source, Occasion with Other's words, Starting piece, Comfort, Colour, and
///   Preferences from the main closet and from a suitcase; the Weather sheet is 5a's;
/// - the stand-in results with the request preview.
@MainActor
@Suite
struct StyleMeSnapshotTests {
    static let width: CGFloat = 402

    // MARK: The page

    @Test func defaultRequest() async {
        assertSnapshot(StyleMePage(model: await loadedStyleMe()), named: "default")
    }

    @Test func defaultRequestDark() async {
        assertSnapshot(StyleMePage(model: await loadedStyleMe()), colorScheme: .dark, named: "default-dark")
    }

    @Test func defaultRequestAX5() async {
        assertSnapshot(
            StyleMePage(model: await loadedStyleMe(startingPieceID: "g-navy-trousers")),
            dynamicTypeSize: .accessibility5, scale: 1, named: "ax5")
    }

    @Test func everyChoiceSet() async {
        let model = await loadedStyleMe(startingPieceID: "g-navy-trousers")
        model.update { draft in
            draft.occasion = .other
            draft.occasionNote = "Museum visit"
            draft.weatherChoice = .indoors
            draft.comfort = .fitted
            draft.color = ColorWish(.pink, strength: .required, scope: .top)
            draft.pieceMode = .onlyMine
        }
        assertSnapshot(StyleMePage(model: model), named: "every-choice")
    }

    @Test func emptyCloset() async {
        assertSnapshot(StyleMePage(model: await loadedStyleMe(styleMeServices(.empty))), named: "empty-closet")
    }

    @Test func emptySuitcase() async {
        let model = await loadedStyleMe()
        model.choose(source: .suitcase("s-spring"))
        assertSnapshot(StyleMePage(model: model), named: "empty-suitcase")
    }

    /// Jose's house: few pieces, the loafers aren't packed there, and nothing purple.
    @Test func smallSuitcaseWithProblems() async {
        let model = await loadedStyleMe(startingPieceID: "g-tan-loafers")
        model.choose(source: .suitcase("s-jose"))
        model.update { $0.color = ColorWish(.purple, strength: .required) }
        assertSnapshot(StyleMePage(model: model), named: "small-suitcase")
    }

    @Test func weatherUnavailableDark() async {
        assertSnapshot(
            StyleMePage(model: await loadedStyleMe(styleMeServices(weather: .unavailable))), colorScheme: .dark,
            named: "weather-unavailable-dark")
    }

    @Test func failed() async {
        assertSnapshot(
            StyleMePage(model: await loadedStyleMe(styleMeServices(behavior: .storesFail))), named: "failed")
    }

    // MARK: Sheets

    @Test func sourceSheet() async {
        let model = await loadedStyleMe()
        model.choose(source: .suitcase("s-weekend"))
        assertSnapshot(sheet(.source, model) { SourceChoices(model: model, close: {}) }, named: "sheet-source")
    }

    @Test func occasionSheetWithOther() async {
        let model = await loadedStyleMe()
        model.update { draft in
            draft.occasion = .other
            draft.occasionNote = "Museum visit"
        }
        assertSnapshot(sheet(.occasion, model) { OccasionChoices(model: model, close: {}) }, named: "sheet-occasion")
    }

    @Test func startingPieceSheet() async {
        let model = await loadedStyleMe(startingPieceID: "g-navy-trousers")
        model.choose(source: .suitcase("s-weekend"))
        assertSnapshot(
            sheet(.startingPiece, model) { StartingPieceChoices(model: model, sourceName: "Weekend", close: {}) },
            named: "sheet-starting-piece")
    }

    @Test func comfortSheet() async {
        let model = await loadedStyleMe()
        model.update { $0.comfort = .fitted }
        assertSnapshot(sheet(.comfort, model) { ComfortChoices(model: model, close: {}) }, named: "sheet-comfort")
    }

    @Test func colorSheet() async {
        let model = await loadedStyleMe()
        model.update { $0.color = ColorWish(.navy, strength: .required, scope: .shoes) }
        assertSnapshot(sheet(.color, model) { ColorChoices(model: model) }, named: "sheet-color")
    }

    @Test func colorSheetNothingPickedDark() async {
        let model = await loadedStyleMe()
        assertSnapshot(
            sheet(.color, model) { ColorChoices(model: model) }, colorScheme: .dark, named: "sheet-color-any-dark")
    }

    @Test func preferencesSheet() async {
        let model = await loadedStyleMe()
        assertSnapshot(
            sheet(.preferences, model) { PreferencesChoices(model: model, sourceName: "Main closet", close: {}) },
            named: "sheet-preferences")
    }

    @Test func preferencesSheetFromASuitcase() async {
        let model = await loadedStyleMe()
        model.choose(source: .suitcase("s-weekend"))
        assertSnapshot(
            sheet(.preferences, model) { PreferencesChoices(model: model, sourceName: "Weekend", close: {}) },
            named: "sheet-preferences-suitcase")
    }

    @Test func sheetsAX5() async {
        let model = await loadedStyleMe()
        model.update { $0.color = ColorWish(.navy) }
        assertSnapshot(
            VStack(spacing: 0) {
                sheet(.comfort, model) { ComfortChoices(model: model, close: {}) }
                sheet(.preferences, model) {
                    PreferencesChoices(model: model, sourceName: "Main closet", close: {})
                }
            },
            dynamicTypeSize: .accessibility5, scale: 1, named: "sheets-ax5")
    }

    // MARK: The stand-in results

    @Test func requestSummary() async throws {
        let model = await loadedStyleMe(startingPieceID: "g-navy-trousers")
        model.update { draft in
            draft.comfort = .comfortable
            draft.color = ColorWish(.navy, scope: .shoes)
        }
        let request = try #require(model.makeRequest(id: "r-checkpoint", now: ClosetTestTime.now))
        let text = model.text(locale: ClosetTestTime.locale)
        let summary = StyleRequestSummary(
            request: request, sourceName: text.sourceName, startingPieceName: model.startingPiece?.name,
            occasionValue: text.occasionValue, locale: ClosetTestTime.locale)
        assertSnapshot(StyleRequestSummaryScreen(summary: summary), named: "summary")
    }

    // MARK: Helpers

    private func sheet(_ sheet: StyleMeSheet, _ model: StyleMeModel, @ViewBuilder content: () -> some View)
        -> some View
    {
        NookSheetContainer(
            title: sheet.title,
            subtitle: sheet.subtitle(sourceName: model.text(locale: ClosetTestTime.locale).sourceName),
            content: content
        )
        .background(Color.nook.wallGradient)
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
