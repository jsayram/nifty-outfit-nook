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

/// Phase 33b: the try-on camera's hints, the check before a photo is saved, and the corrected
/// consent text, compared with the PNGs in `__Snapshots__/TryOnSetupSnapshotTests`.
///
/// The camera's picture is a drawn stand-in (`DrawnFigure`), never a photo of anyone, and the
/// frames are scripted, so every hint is drawn from the same rules as on the iPhone. Drawn 402
/// points wide (iPhone 17) at 1x. The camera screens are the whole screen, 874 points tall.
@MainActor
@Suite(.heavyMainActorWork)
struct TryOnSetupSnapshotTests {
    static let width: CGFloat = 402
    private let us = Locale(identifier: "en_US")
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Live hints

    private func captureModel(_ seen: FramingObservation, counting seconds: Double? = nil) -> TryOnCaptureModel {
        let source = ScriptedFrameSource()
        let model = TryOnCaptureModel(source: source, phase: .running)
        model.receive(seen, at: start)
        model.receive(seen, at: start.addingTimeInterval(0.2))
        if let seconds { _ = model.tick(at: start.addingTimeInterval(seconds)) }
        return model
    }

    private func capture(_ model: TryOnCaptureModel) -> some View {
        TryOnCaptureScreen(makeModel: { model }, photoTaken: { _ in }, close: {})
    }

    private let good = FramingSamples.good

    @Test func stepBack() {
        assertSnapshot(
            capture(captureModel(FramingSamples.cutOff)), colorScheme: .dark, height: 874, named: "hint-step-back")
    }

    @Test func armsOut() {
        assertSnapshot(
            capture(captureModel(FramingSamples.armsClose)), colorScheme: .dark, height: 874, named: "hint-arms-out")
    }

    @Test func moreLight() {
        assertSnapshot(
            capture(captureModel(FramingSamples.dark)), colorScheme: .dark, height: 874, named: "hint-more-light")
    }

    @Test func readyWithTheTimerRunning() {
        // Good for a second, then the countdown: 2 seconds left.
        assertSnapshot(
            capture(captureModel(good, counting: 2.5)), colorScheme: .dark, height: 874, named: "hint-ready-countdown")
    }

    @Test func hintsThatCantRun() {
        let model = captureModel(good)
        for index in 0..<TryOnCaptureModel.missesBeforeOff {
            model.receive(nil, at: start.addingTimeInterval(Double(index)))
        }
        assertSnapshot(capture(model), colorScheme: .dark, height: 874, named: "hints-off")
    }

    // MARK: The check before she saves it

    private func sheet(
        step: TryOnPhotoSheet.Step, check: TryOnPhotoCheck? = nil, source: PhotoSource = .camera
    ) -> some View {
        let candidate = check.map {
            TryOnPhotoCandidate(photo: DrawnPersonProvider.reference, source: source, check: $0)
        }
        return NookSheetContainer(title: ProfileText.photoRow, subtitle: nil) {
            TryOnPhotoSheet(
                hasPhoto: true, step: step, ownPhoto: Self.ownPhoto, candidate: candidate, useExample: { true },
                remove: { true })
        }
        .background(Color.nook.wallGradient)
    }

    private static let ownPhoto = OwnTryOnPhoto(
        photo: DrawnPersonProvider.reference, frames: nil, prepare: { _ in nil }, check: { _ in .fine(tips: []) },
        save: { _ in true }, discard: { _ in })

    @Test func setUpWithTheCamera() {
        assertSnapshot(sheet(step: .main), named: "sheet-main")
    }

    @Test func checking() {
        assertSnapshot(sheet(step: .checking), named: "sheet-checking")
    }

    @Test func aPhotoThatWorksWithTips() {
        assertSnapshot(
            sheet(step: .review, check: .fine(tips: [.stepBack, .armsOut])), colorScheme: .dark,
            named: "review-fine-dark")
    }

    @Test func aPhotoThatWorks() {
        assertSnapshot(sheet(step: .review, check: .fine(tips: []), source: .library), named: "review-fine")
    }

    @Test func aPhotoThatWontWork() {
        assertSnapshot(sheet(step: .review, check: .problem(.severalPeople)), named: "review-problem")
    }

    @Test func aCheckThatCouldNotRun() {
        assertSnapshot(
            sheet(step: .review, check: .problem(.checksUnavailable), source: .library), named: "review-unavailable")
    }

    /// AX5 pictures differ between iOS runtimes by more than the tolerance (the snapshots of other
    /// screens at AX5 do), and these were recorded on the iOS 26.5 simulator, so large text is
    /// checked by measuring instead: nothing runs wider than the window.
    @Test func largeTextStillFitsTheWindow() {
        let loader = DrawnPersonProvider.loader
        for (name, view) in [
            ("review-problem", AnyView(sheet(step: .review, check: .problem(.noFace)))),
            ("review-fine", AnyView(sheet(step: .review, check: .fine(tips: [.stepBack, .armsOut])))),
            ("consent", AnyView(TryOnConsentContent(allow: {}, notNow: {}).padding(NookSpacing.large))),
        ] {
            expectFitsWidth(
                view.environment(\.garmentImages, loader).environment(\.scenePhase, .active), width: Self.width,
                dynamicTypeSize: .accessibility5, named: "\(name)-ax5")
        }
    }

    // MARK: The consent text

    @Test func theConsentSaysHowLongTheServerKeepsThePhotos() {
        assertSnapshot(
            TryOnConsentContent(allow: {}, notNow: {})
                .padding(NookSpacing.large)
                .background(Color.nook.wallGradient),
            named: "consent")
    }

    // MARK: Drawing

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        height: CGFloat? = nil,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let loader = DrawnPersonProvider.loader
        if height == nil {
            expectFitsWidth(
                view.environment(\.garmentImages, loader), width: Self.width, colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize, named: name, fileID: fileID, filePath: filePath, line: line,
                column: column)
        }
        let framed = view.frame(width: Self.width, height: height)
        let content =
            (height == nil ? AnyView(framed.fixedSize(horizontal: false, vertical: true)) : AnyView(framed))
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.scenePhase, .active)
            .environment(\.garmentImages, loader)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, 1)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, us)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: height)
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

/// The frames the hint snapshots show: one person in the middle, facing the camera, and what goes
/// wrong with her.
enum FramingSamples {
    private static func joints(armsClose: Bool) -> [FramingObservation.Joint: FramingObservation.Point] {
        typealias Point = FramingObservation.Point
        let reach = armsClose ? 0.09 : 0.22
        return [
            .nose: Point(x: 0.5, y: 0.12), .leftEye: Point(x: 0.48, y: 0.11), .rightEye: Point(x: 0.52, y: 0.11),
            .neck: Point(x: 0.5, y: 0.2), .leftShoulder: Point(x: 0.4, y: 0.22), .rightShoulder: Point(x: 0.6, y: 0.22),
            .leftWrist: Point(x: 0.5 - reach, y: 0.58), .rightWrist: Point(x: 0.5 + reach, y: 0.58),
            .leftHip: Point(x: 0.44, y: 0.54), .rightHip: Point(x: 0.56, y: 0.54),
            .leftAnkle: Point(x: 0.44, y: 0.92), .rightAnkle: Point(x: 0.56, y: 0.92),
        ]
    }

    private static let outline = CGRect(x: 0.3, y: 0.08, width: 0.4, height: 0.86)

    static let good = FramingObservation(people: 1, joints: joints(armsClose: false), outline: outline)
    static let cutOff = FramingObservation(
        people: 1, joints: joints(armsClose: false), outline: CGRect(x: 0.3, y: 0.0, width: 0.4, height: 1.0))
    static let armsClose = FramingObservation(people: 1, joints: joints(armsClose: true), outline: outline)
    static let dark = FramingObservation(
        people: 1, joints: joints(armsClose: false), outline: outline, frameBrightness: 0.1, subjectBrightness: 0.1)
}

/// A drawn stand-in for a photo of her: a plain wall and a simple figure. Never a photo of anyone.
@MainActor
enum DrawnPersonProvider {
    nonisolated static let reference = PhotoReference.stored(EntityID("drawn-person"))

    /// The picture, 3 wide to 4 tall.
    static let image: UIImage = {
        let size = CGSize(width: 300, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(red: 0.83, green: 0.85, blue: 0.82, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.62, green: 0.55, blue: 0.47, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 340, width: 300, height: 60))
            UIColor(red: 0.84, green: 0.7, blue: 0.58, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 135, y: 36, width: 30, height: 38))
            UIColor(red: 0.35, green: 0.45, blue: 0.62, alpha: 1).setFill()
            cg.fill(CGRect(x: 112, y: 82, width: 76, height: 104))
            UIColor(red: 0.84, green: 0.7, blue: 0.58, alpha: 1).setFill()
            cg.fill(CGRect(x: 94, y: 86, width: 12, height: 96))
            cg.fill(CGRect(x: 194, y: 86, width: 12, height: 96))
            UIColor(red: 0.22, green: 0.24, blue: 0.3, alpha: 1).setFill()
            cg.fill(CGRect(x: 116, y: 186, width: 30, height: 140))
            cg.fill(CGRect(x: 154, y: 186, width: 30, height: 140))
        }
    }()

    static let loader: GarmentImageLoader = {
        let loader = GarmentImageLoader(provider: Provider())
        loader.synchronousData = { reference in reference == Self.reference ? image.pngData() : nil }
        return loader
    }()

    private struct Provider: ImageProvider {
        func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
            guard reference == DrawnPersonProvider.reference else { return nil }
            return await MainActor.run { DrawnPersonProvider.image.pngData() }
        }
    }
}
