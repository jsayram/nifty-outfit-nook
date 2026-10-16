import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// The other screens' quick tours (Phase 16b), compared with the PNGs in
/// `__Snapshots__/ScreenTourSnapshotTests`: one key step of each tour over its page on the
/// iPhone 17, App tours, a few at AX5, and two on the 11-inch iPad.
///
/// The page is drawn as a still image below where the bars would be, and the spotlight goes
/// where the page's own anchor is: the anchors report their bounds as a preference
/// (`TourAnchorBounds`), read in the same layout pass. So these check that each step points at
/// the control it names and where its card lands. The UI tests check the anchors on screen.
@MainActor
@Suite(.heavyMainActorWork)
struct ScreenTourSnapshotTests {
    static let phone = PhoneScreen.iPhone17.size
    /// The iPhone 17's safe area, which the card keeps inside.
    static let phoneSafeArea = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    /// The status bar and an inline navigation bar.
    static let barsHeight: CGFloat = 116

    private var services: NookServices {
        FixtureServices.make(set: .demo, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
    }

    private var data: FixtureData {
        FixtureSet.demo.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
    }

    // MARK: Closet and pieces

    @Test func closetSearch() async {
        let model = ClosetModel()
        await model.load(from: services, now: ClosetTestTime.now)
        assertTourSnapshot(
            ClosetPage(model: model, open: { _ in }, retry: {}), ClosetTour.definition(detailBeside: false), step: 1,
            named: "closet-2")
    }

    @Test func closetFiltersAX5() async {
        let model = ClosetModel()
        await model.load(from: services, now: ClosetTestTime.now)
        assertTourSnapshot(
            ClosetPage(model: model, open: { _ in }, retry: {}), ClosetTour.definition(detailBeside: false), step: 2,
            dynamicTypeSize: .accessibility5, named: "closet-3-ax5")
    }

    @Test func garmentStyleWithThis() async {
        let model = GarmentDetailModel(garmentID: "g-navy-trousers")
        await model.load(from: services, now: ClosetTestTime.now)
        assertTourSnapshot(GarmentDetailPage(model: model), GarmentTour.definition, step: 1, named: "garment-2")
    }

    @Test func addPiecePhotos() async {
        let model = await loadedEditor(services: editorServices())
        assertTourSnapshot(GarmentEditorPage(model: model), AddPieceTour.definition, step: 0, named: "add-piece-1")
    }

    // MARK: Style Me

    @Test func styleMeSource() async {
        assertTourSnapshot(
            StyleMePage(model: await loadedStyleMe()), StyleMeTour.definition, step: 0, named: "style-me-1")
    }

    @Test func yourLooksVersions() async {
        assertTourSnapshot(
            YourLooksPage(model: await styledLooks()), YourLooksTour.definition(hasVersions: true), step: 0,
            named: "your-looks-1")
    }

    @Test func yourLooksVersionsDark() async {
        assertTourSnapshot(
            YourLooksPage(model: await styledLooks()), YourLooksTour.definition(hasVersions: true), step: 0,
            colorScheme: .dark, named: "your-looks-1-dark")
    }

    @Test func swapOptions() async throws {
        let looks = await swappableLooks()
        let swap = try #require(looks.swapModel(sourceName: "Main closet"))
        assertTourSnapshot(SwapPage(model: swap), SwapTour.definition, step: 1, named: "swap-2")
    }

    @Test func lookBuilderAddAPiece() async {
        assertTourSnapshot(
            LookBuilderPage(model: await loadedBuilder()), LookBuilderTour.definition, step: 0, named: "builder-1")
    }

    // MARK: Saved Looks

    @Test func savedLooksFirstLook() async {
        let model = SavedLooksModel()
        await model.load(from: services, now: ClosetTestTime.now)
        assertTourSnapshot(SavedLooksPage(model: model), SavedLooksTour.definition, step: 0, named: "saved-looks-1")
    }

    @Test func lookWearToday() async throws {
        let model = LookDetailModel(
            lookID: try #require(data.looks.first?.id), now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar)
        await model.load(from: services)
        assertTourSnapshot(LookDetailPage(model: model), LookTour.definition, step: 0, named: "look-1")
    }

    @Test func pictureSeeTheLook() async throws {
        let model = PictureDetailModel(
            pictureID: try #require(data.pictures.first?.id), now: { ClosetTestTime.now },
            calendar: ClosetTestTime.calendar)
        await model.load(from: services)
        assertTourSnapshot(PictureDetailPage(model: model), PictureTour.definition, step: 0, named: "picture-1")
    }

    // MARK: Suitcases and laundry

    @Test func suitcasesFirstFavourite() async {
        let model = SuitcasesModel()
        await model.load(from: services, now: ClosetTestTime.now)
        assertTourSnapshot(SuitcasesPage(model: model), SuitcasesTour.definition, step: 1, named: "suitcases-2")
    }

    @Test func suitcasePacking() async throws {
        let suitcase = try #require(data.suitcases.first { !$0.isArchived })
        let model = SuitcaseDetailModel(suitcaseID: suitcase.id)
        await model.load(from: services, now: ClosetTestTime.now)
        assertTourSnapshot(
            SuitcaseDetailPage(model: model), SuitcaseTour.definition(hasPieces: true), step: 1, named: "suitcase-2")
    }

    @Test func laundryMarkClean() async {
        let services = FixtureServices.make(
            set: .demo, laundry: .some, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        let model = LaundryModel()
        await model.load(from: services)
        assertTourSnapshot(
            LaundryPage(model: model), LaundryTour.definition(hasScope: model.sourceSuitcase != nil),
            step: model.sourceSuitcase != nil ? 1 : 0, named: "laundry-mark-clean")
    }

    @Test func laundryOff() async {
        let model = LaundryModel()
        await model.load(from: services)
        assertTourSnapshot(LaundryPage(model: model), LaundryTour.offDefinition, step: 0, named: "laundry-off-1")
    }

    // MARK: Profile and settings

    @Test func profileAppTours() async {
        let model = ProfileModel()
        await model.load(from: services, locale: ClosetTestTime.locale)
        assertTourSnapshot(ProfilePage(model: model), ProfileTour.definition, step: 2, named: "profile-3")
    }

    @Test func profileAppToursAX5() async {
        let model = ProfileModel()
        await model.load(from: services, locale: ClosetTestTime.locale)
        assertTourSnapshot(
            ProfilePage(model: model), ProfileTour.definition, step: 0, dynamicTypeSize: .accessibility5,
            named: "profile-1-ax5")
    }

    @Test func fitUsualFit() async {
        let model = ProfileModel()
        await model.load(from: services, locale: ClosetTestTime.locale)
        assertTourSnapshot(FitPage(model: model), FitTour.definition, step: 0, named: "fit-1")
    }

    @Test func helpStillStuck() {
        assertTourSnapshot(
            HelpPage(open: [HelpContent.topics[0].id], version: AppVersion(version: "0.1", build: "1")),
            HelpTour.definition, step: 0, named: "help-1")
    }

    @Test func feedbackNote() {
        assertTourSnapshot(FeedbackTourHost(), FeedbackTour.definition, step: 0, named: "feedback-1")
    }

    @Test func privacyDeleteMyData() {
        assertTourSnapshot(PrivacyPage(), PrivacyTour.definition, step: 1, named: "privacy-2")
    }

    // MARK: App tours

    @Test func appToursSheet() {
        let sheet = NookSheetContainer(title: AppToursText.row, subtitle: AppToursText.sheetLine) {
            AppToursSheet(
                tracksLaundry: false, showsTips: true, replay: { _ in }, setShowsTips: { _ in true },
                resetAll: { true })
        }
        let view =
            sheet
            .frame(width: Self.phone.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.nook.surface)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.locale, ClosetTestTime.locale)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: Self.phone.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image")
            return
        }
        assertSnapshot(of: image, as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: 2), named: "app-tours")
    }

    // MARK: iPad

    /// Your looks beside its buttons on the 11-inch iPad held sideways.
    @Test func yourLooksOnIPad() async {
        assertTourSnapshot(
            YourLooksPage(model: await styledLooks()), YourLooksTour.definition(hasVersions: true), step: 2,
            size: SnapshotWindow.landscape.size, safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
            barsHeight: 86, sizeClass: .regular, scale: 1, named: "your-looks-3-ipad")
    }

    @Test func fitOnIPadUpright() async {
        let model = ProfileModel()
        await model.load(from: services, locale: ClosetTestTime.locale)
        assertTourSnapshot(
            FitPage(model: model), FitTour.definition, step: 3, size: SnapshotWindow.portrait.size,
            safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), barsHeight: 86, sizeClass: .regular,
            scale: 1, named: "fit-4-ipad")
    }

    // MARK: Helper

    /// Draws `page` below the bars with step `step` of `tour` over it, the spotlight on the
    /// page's own anchor for that step.
    private func assertTourSnapshot(
        _ page: some View,
        _ tour: TourDefinition,
        step index: Int,
        size: CGSize = Self.phone,
        safeArea: EdgeInsets = Self.phoneSafeArea,
        barsHeight: CGFloat = Self.barsHeight,
        sizeClass: UserInterfaceSizeClass = .compact,
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
        let tourStep = tour.steps[index]
        let card = NookTourStep(
            title: tourStep.title, message: tourStep.message, index: index, count: tour.steps.count,
            finishTitle: tour.finishTitle)
        let view =
            page
            .padding(.top, barsHeight)
            .frame(width: size.width, height: size.height, alignment: .top)
            .overlayPreferenceValue(TourAnchorBounds.self) { anchors in
                GeometryReader { proxy in
                    NookTourOverlay(
                        step: card, target: anchors[tourStep.anchor].map { proxy[$0] }, safeArea: safeArea,
                        onNext: {}, onBack: {}, onSkip: {}, onTarget: {})
                }
            }
            .clipped()
            .background(Color.nook.wallGradient)
            .dynamicTypeSize(dynamicTypeSize)
            .environment(\.horizontalSizeClass, sizeClass)
            // Fit and measurements is covered unless the app is active (Phase 14a).
            .environment(\.scenePhase, .active)
            .environment(\.closetIsStillImage, true)
            .environment(\.roomIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, ClosetTestTime.locale)
            .environment(\.calendar, ClosetTestTime.calendar)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        assertSnapshot(
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

/// Send feedback's page with the focus state it needs.
private struct FeedbackTourHost: View {
    @State private var model = FeedbackModel()
    @AccessibilityFocusState private var focus: FeedbackField?

    var body: some View {
        FeedbackPage(model: model, focus: $focus)
    }
}
