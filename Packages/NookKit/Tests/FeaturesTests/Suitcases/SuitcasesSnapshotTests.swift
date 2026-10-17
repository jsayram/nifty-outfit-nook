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

/// Suitcases, a suitcase, its sheets and Laundry (Phase 13), compared with the PNGs in
/// `__Snapshots__/SuitcasesSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars:
/// - Suitcases: the demo with Jose's house as the source, the same in dark, AX5 (no hall), and
///   no suitcases yet; All suitcases with the archived filter on.
/// - A suitcase: Jose's house as the source, Weekend in dark with tracking on, Spring trip empty,
///   and Old dorm archived; the packing sheet and the name and picture sheet.
/// - Laundry: two in the wash with a suitcase source, the same at AX5, all clean in dark,
///   tracking off, and the confirmation.
///
/// Each page is also checked for width: offered 402 points, it mustn't be wider (`expectFitsWidth`).
@MainActor
@Suite(.heavyMainActorWork)
struct SuitcasesSnapshotTests {
    static let width: CGFloat = 402
    private let now = TestTime.now

    private func data(source: Bool = true, tracksLaundry: Bool = false) -> FixtureData {
        var data = FixtureSet.demo.data(now: now, calendar: TestTime.calendar)
        if source { data.profile.remembered.source = .suitcase("s-jose") }
        data.profile.preferences.tracksLaundry = tracksLaundry
        data.garments.sort { $0.addedAt > $1.addedAt }
        return data
    }

    private func suitcases(_ data: FixtureData) -> SuitcasesModel {
        let model = SuitcasesModel()
        model.show(suitcases: data.suitcases, garments: data.garments, profile: data.profile, now: now)
        return model
    }

    private func detail(_ id: Suitcase.ID, _ data: FixtureData) -> SuitcaseDetailModel {
        let model = SuitcaseDetailModel(suitcaseID: id)
        model.show(suitcases: data.suitcases, garments: data.garments, profile: data.profile, now: now)
        return model
    }

    private func laundry(_ data: FixtureData) -> LaundryModel {
        let model = LaundryModel()
        model.show(garments: data.garments, suitcases: data.suitcases, profile: data.profile)
        return model
    }

    // MARK: Suitcases

    @Test func suitcases() {
        assertSnapshot(SuitcasesPage(model: suitcases(data())), named: "suitcases")
        assertSnapshot(SuitcasesPage(model: suitcases(data())), colorScheme: .dark, named: "suitcases-dark")
    }

    @Test func suitcasesAX5() {
        assertSnapshot(
            SuitcasesPage(model: suitcases(data(source: false))), dynamicTypeSize: .accessibility5,
            named: "suitcases-ax5")
    }

    @Test func noSuitcasesYet() {
        let empty = FixtureSet.empty.data(now: now, calendar: TestTime.calendar)
        assertSnapshot(SuitcasesPage(model: suitcases(empty)), named: "none")
    }

    @Test func allSuitcasesWithArchived() {
        let model = suitcases(data())
        model.showsArchived = true
        assertSnapshot(AllSuitcasesPage(model: model), named: "all")
    }

    // MARK: A suitcase

    /// A suitcase and All suitcases at AX5 have no picture of their own, but stay inside the
    /// window (QA, October 2026).
    @Test func suitcaseAndAllSuitcasesFitAtAX5() {
        let data = data(tracksLaundry: true)
        expectFitsWidth(
            SuitcaseDetailPage(model: detail("s-jose", data)), width: Self.width, dynamicTypeSize: .accessibility5,
            named: "jose-ax5")
        let all = suitcases(data)
        all.showsArchived = true
        expectFitsWidth(
            AllSuitcasesPage(model: all), width: Self.width, dynamicTypeSize: .accessibility5, named: "all-ax5")
    }

    @Test func theSourceSuitcase() {
        assertSnapshot(SuitcaseDetailPage(model: detail("s-jose", data())), named: "jose")
    }

    @Test func anotherSuitcaseInDark() {
        assertSnapshot(
            SuitcaseDetailPage(model: detail("s-weekend", data(tracksLaundry: true))), colorScheme: .dark,
            named: "weekend-dark")
    }

    @Test func emptyAndArchived() {
        let data = data()
        assertSnapshot(
            VStack(spacing: 0) {
                SuitcaseDetailPage(model: detail("s-spring", data))
                SuitcaseDetailPage(model: detail("s-old-dorm", data))
            },
            named: "empty-and-archived")
    }

    @Test func packingSheet() {
        let model = detail("s-jose", data())
        assertSnapshot(
            NookSheetContainer(title: "Pack Jose's house") {
                PackingSheet(model: model, list: model.packingList(), toggle: { _ in })
            }
            .background(Color.nook.wallGradient),
            named: "packing")
    }

    @Test func nameAndPictureSheet() {
        assertSnapshot(
            VStack(spacing: 0) {
                NookSheetContainer(title: "Add a suitcase", subtitle: "Give it a name and a picture.") {
                    SuitcaseEditor(purpose: .add, problem: { _ in nil }, save: { _, _ in true })
                }
                NookSheetContainer(title: "Name and picture") {
                    SuitcaseEditor(
                        purpose: .edit, name: "Weekend", icon: .duffel, problem: { _ in .duplicate },
                        save: { _, _ in true })
                }
            }
            .background(Color.nook.wallGradient),
            named: "editor")
    }

    // MARK: Laundry

    @Test func laundryWithASuitcaseSource() {
        assertSnapshot(LaundryPage(model: laundry(data(tracksLaundry: true))), named: "laundry")
    }

    /// The rows stack at AX5, so the page stays inside the window (QA, October 2026).
    @Test func laundryAX5() {
        assertSnapshot(
            LaundryPage(model: laundry(data(source: false, tracksLaundry: true))), dynamicTypeSize: .accessibility5,
            named: "laundry-ax5")
    }

    @Test func laundryAllCleanInDarkAndOff() {
        var clean = data(source: false, tracksLaundry: true)
        for index in clean.garments.indices { clean.garments[index].laundry = .clean }
        assertSnapshot(LaundryPage(model: laundry(clean)), colorScheme: .dark, named: "laundry-clean-dark")
        assertSnapshot(LaundryPage(model: laundry(data(source: false))), named: "laundry-off")
    }

    @Test func laundryConfirmation() {
        let model = laundry(data(tracksLaundry: true))
        let request = CleanRequest(kind: .all, ids: model.shown.map(\.id), scopeName: "Main closet")
        assertSnapshot(
            NookSheetContainer(title: request.title) {
                CleanConfirmation(request: request, model: model, confirm: {}, cancel: {})
            }
            .background(Color.nook.wallGradient),
            named: "laundry-confirm")
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
            .environment(\.displayScale, 1)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, TestTime.locale)
            .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: content.snapshotPhotos())
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        SnapshotTesting.assertSnapshot(
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
