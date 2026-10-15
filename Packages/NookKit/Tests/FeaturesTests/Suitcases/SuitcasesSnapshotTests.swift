import DesignSystem
import Fixtures
import Models
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
/// - Laundry: two in the wash with a suitcase source, all clean in dark, tracking off, and the
///   confirmation.
@MainActor
@Suite
struct SuitcasesSnapshotTests {
    static let width: CGFloat = 402
    private let now = ClosetTestTime.now

    private func data(source: Bool = true, tracksLaundry: Bool = false) -> FixtureData {
        var data = FixtureSet.demo.data(now: now, calendar: ClosetTestTime.calendar)
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
        let empty = FixtureSet.empty.data(now: now, calendar: ClosetTestTime.calendar)
        assertSnapshot(SuitcasesPage(model: suitcases(empty)), named: "none")
    }

    @Test func allSuitcasesWithArchived() {
        let model = suitcases(data())
        model.showsArchived = true
        assertSnapshot(AllSuitcasesPage(model: model), named: "all")
    }

    // MARK: A suitcase

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
        let content =
            view
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, 2)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, ClosetTestTime.locale)
            .environment(\.calendar, ClosetTestTime.calendar)
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
