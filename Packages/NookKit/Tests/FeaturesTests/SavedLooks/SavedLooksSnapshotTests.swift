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

/// Saved Looks, look detail (Phase 12a), the Pictures tab, picture detail and Try it on
/// (Phase 12b), compared with the PNGs in `__Snapshots__/SavedLooksSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars, from
/// the demo closet:
/// - the grid in light, dark and AX5, filtered to black bottoms, with no matches, and empty;
/// - the Pictures tab in light, dark and AX5, and empty;
/// - look detail for the Interview look, with its two pictures (light, dark, AX5), and for the
///   Gray blazer office look, whose blazer she gave away (faded, with Swap it);
/// - picture detail (light, dark, AX5), a picture of an earlier version, and one whose look was
///   deleted; a picture hidden while the app isn't active;
/// - the Try it on sheet from Your looks, and with a picture she already has.
@MainActor
@Suite(.heavyMainActorWork)
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

    // MARK: Pictures (12b)

    @Test func pictures() async {
        let model = await loadedSavedLooks()
        model.tab = .pictures
        assertSnapshot(SavedLooksPage(model: model), named: "pictures")
    }

    @Test func picturesDark() async {
        let model = await loadedSavedLooks()
        model.tab = .pictures
        assertSnapshot(SavedLooksPage(model: model), colorScheme: .dark, named: "pictures-dark")
    }

    @Test func picturesAX5() async {
        let model = await loadedSavedLooks()
        model.tab = .pictures
        assertSnapshot(SavedLooksPage(model: model), dynamicTypeSize: .accessibility5, scale: 1, named: "pictures-ax5")
    }

    /// No pictures yet: what a picture is, that it needs a look, and how to make one.
    @Test func picturesEmpty() async {
        let model = await loadedSavedLooks(.empty)
        model.tab = .pictures
        assertSnapshot(SavedLooksPage(model: model), named: "pictures-empty")
    }

    @Test func pictureDetail() async {
        assertSnapshot(PictureDetailPage(model: await picture("p-interview")), named: "picture")
    }

    @Test func pictureDetailDark() async {
        assertSnapshot(
            PictureDetailPage(model: await picture("p-interview")), colorScheme: .dark, named: "picture-dark")
    }

    @Test func pictureDetailAX5() async {
        assertSnapshot(
            PictureDetailPage(model: await picture("p-interview")), dynamicTypeSize: .accessibility5, scale: 1,
            named: "picture-ax5")
    }

    /// A picture of an earlier version: the cream sweater, and the note under the look.
    @Test func pictureOfAnEarlierVersion() async {
        assertSnapshot(PictureDetailPage(model: await picture("p-interview-earlier")), named: "picture-earlier")
    }

    /// Its look was deleted: no See the look, and the picture stays.
    @Test func pictureWhoseLookWasDeleted() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        try await services.looks.delete("o-lace-date")
        assertSnapshot(
            PictureDetailPage(model: await picture("p-lace", services: services)), named: "picture-look-deleted")
    }

    /// SECURITY_STANDARD §4: a picture is hidden while the app isn't active, so the app switcher's
    /// snapshot doesn't keep it.
    @Test func pictureHiddenInTheAppSwitcher() async {
        assertSnapshot(
            PictureDetailPage(model: await picture("p-interview")), scenePhase: .inactive, named: "picture-hidden")
    }

    /// Try it on from Your looks for a look that isn't saved: what happens, that it saves the
    /// look, and that it's free here.
    @Test func tryOnSheet() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let look = try await services.looks.look("o-history-casual")
        let model = TryOnModel(look: look, lookName: "Cream & denim", garments: [:], saveLook: { look })
        assertSnapshot(tryOnSheet(model), named: "try-on")
    }

    /// FR-59: she already has a picture of this look.
    @Test func tryOnSheetWithAPictureSheHas() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let look = try await services.looks.look("o-interview")
        let garments = try await services.closet.garments()
        let model = TryOnModel(
            look: look, lookName: "Interview navy and pink",
            garments: Dictionary(uniqueKeysWithValues: garments.map { ($0.id, $0) }))
        await model.start(with: services)
        assertSnapshot(tryOnSheet(model), named: "try-on-already-made")
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

    private func picture(_ id: TryOnPicture.ID, services: NookServices? = nil) async -> PictureDetailModel {
        let services =
            services ?? FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let model = PictureDetailModel(pictureID: id, now: { TestTime.now }, calendar: TestTime.calendar)
        await model.load(from: services)
        return model
    }

    /// The sheet's header and content, as the sheet shows them, on the wall.
    private func tryOnSheet(_ model: TryOnModel) -> some View {
        NookSheetContainer(title: TryOnText.tryOn, subtitle: TryOnText.simulated) {
            TryOnSheetContent(model: model, seePicture: { _ in })
        }
        .background(Color.nook.wallGradient)
    }

    private func detail(_ id: Look.ID) async -> LookDetailModel {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let model = LookDetailModel(lookID: id, now: { TestTime.now }, calendar: TestTime.calendar)
        await model.load(from: services)
        return model
    }

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        scale: CGFloat = 2,
        scenePhase: ScenePhase = .active,
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
            .environment(\.scenePhase, scenePhase)
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
