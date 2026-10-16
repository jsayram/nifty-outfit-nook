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

/// Garment detail (Phase 7a), its sheets and Recently deleted, compared with the PNGs in
/// `__Snapshots__/GarmentDetailSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars:
/// - Navy dress pants: a bottom worn 5 days ago (the recent-wear note), in two suitcases and two
///   saved looks; the same at AX5.
/// - White lace top in dark with laundry tracking on: in the wash, worn 10 weeks ago.
/// - Tan loafers: shoes, never marked as worn, no picture, no suitcase.
/// - Blue floral dress: two colours with her note, away at the tailor, in one suitcase.
/// - The gone and error states, the Remove from closet and Style with this sheets, and Recently
///   deleted.
@MainActor
@Suite(.heavyMainActorWork)
struct GarmentDetailSnapshotTests {
    static let width: CGFloat = 402

    private func model(_ id: Garment.ID, tracksLaundry: Bool = false) throws -> GarmentDetailModel {
        var data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        data.profile.preferences.tracksLaundry = tracksLaundry
        let garment = try #require(data.garments.first { $0.id == id })
        let looks = data.looks.sorted { $0.createdAt > $1.createdAt }
        let model = GarmentDetailModel(garmentID: id)
        model.show(garment, suitcases: data.suitcases, looks: looks, profile: data.profile, now: TestTime.now)
        return model
    }

    @Test func navyTrousers() throws {
        assertSnapshot(GarmentDetailPage(model: try model("g-navy-trousers")), named: "navy-trousers")
    }

    @Test func navyTrousersAX5() throws {
        assertSnapshot(
            GarmentDetailPage(model: try model("g-navy-trousers")), dynamicTypeSize: .accessibility5, named: "ax5")
    }

    @Test func laceTopInTheWashDark() throws {
        assertSnapshot(
            GarmentDetailPage(model: try model("g-lace-top", tracksLaundry: true)), colorScheme: .dark,
            named: "lace-top-dirty-dark")
    }

    @Test func tanLoafersNeverWorn() throws {
        assertSnapshot(GarmentDetailPage(model: try model("g-tan-loafers")), named: "tan-loafers")
    }

    @Test func blueDressAway() throws {
        assertSnapshot(GarmentDetailPage(model: try model("g-blue-dress")), named: "blue-dress")
    }

    @Test func goneAndFailed() async {
        let gone = GarmentDetailModel(garmentID: "g-nothing")
        await gone.load(from: garmentTestServices(), now: TestTime.now)
        let failed = GarmentDetailModel(garmentID: "g-navy-trousers")
        await failed.load(from: garmentTestServices(behavior: .storesFail), now: TestTime.now)
        assertSnapshot(
            VStack(spacing: 0) {
                GarmentDetailPage(model: gone)
                GarmentDetailPage(model: failed)
            },
            named: "gone-and-failed")
    }

    /// LR-16: the choices, then Delete it listing the saved looks it affects.
    @Test func removeFromClosetSheet() throws {
        let model = try model("g-navy-trousers")
        func sheet(_ step: RemoveFromClosetChoices.Step) -> some View {
            NookSheetContainer(title: "Remove from closet", subtitle: "Navy dress pants") {
                RemoveFromClosetChoices(
                    name: "Navy dress pants", deadline: "Nov 13", savedLookNames: model.savedLookNames,
                    isSaving: false, step: step, confirmNoLongerOwned: {}, confirmDelete: {})
            }
            .background(Color.nook.wallGradient)
        }
        assertSnapshot(
            VStack(spacing: 0) {
                sheet(.choose)
                sheet(.confirmNoLongerOwned)
                sheet(.confirmDelete)
            },
            named: "remove-sheet")
    }

    @Test func styleWithThisSheet() {
        assertSnapshot(
            NookSheetContainer(title: "Style with this", subtitle: "Navy dress pants") {
                StyleWithThisChoices { _ in }
            }
            .background(Color.nook.wallGradient),
            named: "style-with-this")
    }

    /// Add to a suitcase (Phase 13): every active suitcase, with a tick where it's packed.
    @Test func addToSuitcaseSheet() throws {
        let model = try model("g-navy-trousers")
        assertSnapshot(
            NookSheetContainer(title: "Add to a suitcase", subtitle: "The piece stays in your closet.") {
                AddToSuitcaseSheet(model: model, toggle: { _ in }, openSuitcases: {})
            }
            .background(Color.nook.wallGradient),
            named: "add-to-suitcase")
    }

    @Test func recentlyDeleted() {
        var data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        if let index = data.garments.firstIndex(where: { $0.id == "g-navy-trousers" }) {
            data.garments[index].deletedAt = TestTime.now
        }
        let model = RecentlyDeletedModel()
        model.show(data.garments, now: TestTime.now)
        assertSnapshot(RecentlyDeletedPage(model: model), named: "recently-deleted")
    }

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
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
            .environment(\.displayScale, 2)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, TestTime.locale)
            .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        SnapshotTesting.assertSnapshot(
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
