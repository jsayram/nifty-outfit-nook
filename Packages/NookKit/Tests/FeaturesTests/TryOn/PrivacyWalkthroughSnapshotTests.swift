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

/// Phase 33c: key frames of the privacy walkthrough and the loading screen's steps, compared with
/// the PNGs in `__Snapshots__/PrivacyWalkthroughSnapshotTests`. The figure is drawn (never a photo
/// of anyone). 402 points wide (iPhone 17) at 1x. Large text is checked by measuring, since AX5
/// pictures differ between iOS runtimes (these were recorded on the 26.5 simulator).
@MainActor
@Suite(.heavyMainActorWork)
struct PrivacyWalkthroughSnapshotTests {
    static let width: CGFloat = 402
    private let us = Locale(identifier: "en_US")

    private func walkthrough(_ beat: WalkthroughBeat, canSkip: Bool = false) -> some View {
        PrivacyWalkthroughView(canSkip: canSkip, beat: beat, finished: { _ in })
            .padding(NookSpacing.large)
            .background(Color.nook.wallGradient)
    }

    // MARK: Key frames

    @Test func theVeilCoversHerHead() {
        assertSnapshot(walkthrough(.veil), named: "beat-veil")
    }

    @Test func thePhotoGoesToTheImageService() {
        assertSnapshot(walkthrough(.sent), colorScheme: .dark, named: "beat-sent-dark")
    }

    @Test func herFaceComesBackOnThePhone() {
        assertSnapshot(walkthrough(.faceBack), named: "beat-face-back")
    }

    @Test func aReplayHasSkip() {
        assertSnapshot(walkthrough(.backdrop, canSkip: true), named: "beat-backdrop-replay-skip")
    }

    /// Reduce Motion: the same frames, with a fade and nothing sliding. The figure stays where it
    /// is, faint, with the cloud over it.
    @Test func reduceMotionKeepsTheFigureInPlace() {
        let stage = WalkthroughStageView(frame: WalkthroughBeat.sent.frame, reduceMotion: true)
            .frame(width: 240)
            .padding(NookSpacing.large)
            .background(Color.nook.wallGradient)
        assertSnapshot(stage, named: "stage-sent-reduce-motion")
    }

    // MARK: The loading screen's steps

    private func steps(_ progress: TryOnProgress) -> some View {
        VStack(spacing: NookSpacing.large) {
            NookLoadingState(TryOnStepText.headline(progress), message: TryOnStepText.message(progress))
            TryOnStepsList(progress: progress)
        }
        .padding(NookSpacing.large)
        .background(Color.nook.wallGradient)
    }

    @Test func thePhoneIsSwappingInTheBackdrop() {
        assertSnapshot(steps(.preparing(.studioBackdrop)), named: "steps-studio-backdrop")
    }

    @Test func theImageServiceIsDressingHer() {
        assertSnapshot(steps(.preparing(.dressing)), colorScheme: .dark, named: "steps-dressing-dark")
    }

    @Test func aFailureStopsAtItsStep() {
        assertSnapshot(
            TryOnStepsList(progress: .stopped(at: .restoring)).padding(NookSpacing.large), named: "steps-stopped")
    }

    @Test func largeTextStillFitsTheWindow() {
        for (name, view) in [
            ("walkthrough", AnyView(walkthrough(.faceBack, canSkip: true))),
            ("steps", AnyView(steps(.preparing(.studioBackdrop)))),
            ("stopped", AnyView(TryOnStepsList(progress: .stopped(at: .restoring)).padding(NookSpacing.large))),
        ] {
            expectFitsWidth(view, width: Self.width, dynamicTypeSize: .accessibility5, named: "\(name)-ax5")
        }
    }

    // MARK: Drawing

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
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
            .environment(\.displayScale, 1)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, us)
        let renderer = ImageRenderer(content: content)
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
