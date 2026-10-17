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

/// Profile, Fit and measurements and their sheets (Phase 14a), compared with the PNGs in
/// `__Snapshots__/ProfileSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars:
/// - Profile: the demo in light, dark and AX5, and a fresh install (no name, so the sign says
///   Hello) with the example photo added.
/// - Fit: made-up measurements in inches and in centimetres (dark), AX5, a fresh install with the
///   example line, and the cover the app switcher sees.
/// - Sheets: the name with a problem, a measurement with a problem, height in feet and inches with
///   a problem, a fitting piece with problems, and the try-on photo sheet empty, added and asking
///   before removing.
@MainActor
@Suite(.heavyMainActorWork)
struct ProfileSnapshotTests {
    static let width: CGFloat = 402
    private let us = Locale(identifier: "en_US")

    /// Synthetic values only (`docs/models.md`, decision 1).
    private static let measurements = BodyMeasurements(
        height: Length(160, .centimeters), waist: Length(27, .inches), hips: Length(36.5, .inches),
        inseam: Length(27, .inches), weight: Weight(130, .pounds))

    private func model(
        _ set: FixtureSet = .demo, measured: Bool = false, units: MeasurementUnits? = nil, photo: Bool = false
    ) -> ProfileModel {
        var profile = set.data(now: TestTime.now, calendar: TestTime.calendar).profile
        if measured { profile.measurements = Self.measurements }
        profile.units = units
        if photo { profile.tryOnPhoto = ProfileModel.exampleTryOnPhoto }
        let model = ProfileModel()
        model.show(profile, locale: us)
        return model
    }

    // MARK: Profile

    @Test func profile() {
        assertSnapshot(ProfilePage(model: model()), named: "profile")
        assertSnapshot(ProfilePage(model: model(photo: true)), colorScheme: .dark, named: "profile-dark")
    }

    @Test func profileAX5() {
        assertSnapshot(ProfilePage(model: model()), dynamicTypeSize: .accessibility5, named: "profile-ax5")
    }

    @Test func freshInstallSaysHello() {
        assertSnapshot(ProfilePage(model: model(.empty, photo: true)), named: "profile-empty")
    }

    // MARK: Fit and measurements

    @Test func fit() {
        assertSnapshot(FitPage(model: model(measured: true)), named: "fit")
        assertSnapshot(
            FitPage(model: model(measured: true, units: .metric)), colorScheme: .dark, named: "fit-metric-dark")
    }

    @Test func fitAX5() {
        assertSnapshot(
            FitPage(model: model(measured: true)), dynamicTypeSize: .accessibility5, named: "fit-ax5")
    }

    @Test func fitWithNothingYet() {
        // LR-13.3: the example line shows only while there are no fitting pieces.
        assertSnapshot(FitPage(model: model(.empty)), named: "fit-empty")
    }

    @Test func fitIsHiddenInTheAppSwitcher() {
        // SECURITY_STANDARD §4: measurements are covered while the app isn't active.
        assertSnapshot(FitPage(model: model(measured: true)), scenePhase: .inactive, named: "fit-hidden")
    }

    // MARK: Sheets

    @Test func nameSheetWithAProblem() {
        let long = "Lily Rose Marguerite Anne"
        assertSnapshot(
            sheet(ProfileSheet.name.title, subtitle: ProfileSheet.name.subtitle) {
                NameSignSheet(name: long, problem: { _ in .tooLong(maximum: 20) }, save: { _ in true })
            },
            named: "name-problem")
    }

    @Test func measurementSheetsWithProblems() {
        var waist = MeasurementForm(field: .waist, measurements: BodyMeasurements(), units: .imperial, locale: us)
        waist.text = "270"
        var height = MeasurementForm(
            field: .height, measurements: Self.measurements, units: .imperial, locale: us)
        height.inches = "14"
        assertSnapshot(
            VStack(spacing: 0) {
                sheet(FitText.name(.waist), subtitle: "\(FitText.help(.waist)) \(FitText.leaveEmpty)") {
                    MeasurementSheet(form: waist, problem: .outOfRange, save: { _ in true }, clear: { true })
                }
                sheet(FitText.name(.height), subtitle: "\(FitText.help(.height)) \(FitText.leaveEmpty)") {
                    MeasurementSheet(form: height, problem: .inchesPart, save: { _ in true }, clear: { true })
                }
            },
            named: "measurement-problems")
    }

    @Test func measurementSheetAX5() {
        var height = MeasurementForm(field: .height, measurements: BodyMeasurements(), units: .imperial, locale: us)
        height.feet = "4"
        height.inches = "11"
        assertSnapshot(
            sheet(FitText.name(.height)) {
                MeasurementSheet(form: height, save: { _ in true }, clear: { true })
            },
            dynamicTypeSize: .accessibility5, named: "measurement-ax5")
    }

    @Test func fittingPieceSheetWithProblems() {
        assertSnapshot(
            sheet(FitText.addPiece) {
                FitPieceSheet(brand: "", size: "", showsProblems: true, add: { _ in true })
            },
            named: "fit-piece-problems")
    }

    @Test func tryOnPhotoSheet() {
        assertSnapshot(
            sheet(ProfileText.photoRow) {
                TryOnPhotoSheet(hasPhoto: false, useExample: { true }, remove: { true })
            },
            named: "try-on-photo-empty")
        assertSnapshot(
            VStack(spacing: 0) {
                sheet(ProfileText.photoRow) {
                    TryOnPhotoSheet(hasPhoto: true, useExample: { true }, remove: { true })
                }
                sheet(ProfileText.photoRow) {
                    TryOnPhotoSheet(hasPhoto: true, step: .remove, useExample: { true }, remove: { true })
                }
            },
            colorScheme: .dark, named: "try-on-photo-added-dark")
    }

    @Test func tryOnPhotoSheetAX5() {
        assertSnapshot(
            sheet(ProfileText.photoRow) {
                TryOnPhotoSheet(hasPhoto: true, step: .example, useExample: { true }, remove: { true })
            },
            dynamicTypeSize: .accessibility5, named: "try-on-photo-example-ax5")
    }

    // MARK: Drawing

    private func sheet<Content: View>(
        _ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        NookSheetContainer(title: title, subtitle: subtitle, content: content)
            .background(Color.nook.wallGradient)
    }

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        scenePhase: ScenePhase = .active,
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
            .environment(\.scenePhase, scenePhase)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, scale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, us)
            .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: content)
        // Drawn at 1x, like every screen snapshot (DesignSystem README, "Snapshot policy"). A very
        // tall page (Fit at AX5) comes back empty at 2x anyway (playbook, Phase 7b).
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
