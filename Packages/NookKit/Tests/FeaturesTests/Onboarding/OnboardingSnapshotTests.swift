import DesignSystem
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Phase 17's onboarding, compared with the PNGs in `__Snapshots__/OnboardingSnapshotTests`.
///
/// - The welcome on the iPhone 17 (402 x 874, without the system bars) in light and dark, at AX5
///   (taller, so it scrolls), and on an iPhone SE (375 x 667).
/// - Each step at full height: the name with "Lily" typed and with a name that's too long, the
///   privacy step, the fit step with Comfortable chosen, and the starting closet with the sample
///   chosen; then the empty closet in dark, the privacy step in dark, and the name and privacy
///   steps at AX5.
/// - On the 11-inch iPad: the welcome upright and sideways, and the privacy step sideways.
@MainActor
@Suite(.heavyMainActorWork)
struct OnboardingSnapshotTests {
    static let phone = CGSize(width: 402, height: 874)
    private let us = Locale(identifier: "en_US")

    private func model(name: String = "", fit: Comfort? = nil, closet: StartingCloset = .sample) -> OnboardingModel {
        OnboardingModel(name: name, usualFit: fit, startingCloset: closet)
    }

    private var welcomeView: some View {
        WelcomeView(getStarted: {}, alreadyUsing: {})
    }

    // MARK: Welcome

    @Test func welcomeScreen() {
        assertSnapshot(welcomeView, height: Self.phone.height, named: "welcome")
        assertSnapshot(welcomeView, height: Self.phone.height, colorScheme: .dark, named: "welcome-dark")
    }

    @Test func welcomeOnASmallPhone() {
        assertSnapshot(welcomeView, width: 375, height: 667, named: "welcome-se")
    }

    @Test func welcomeAX5() {
        // The words take what they need and the porch gets smaller; the page is taller than the
        // screen, so it scrolls there.
        assertSnapshot(
            welcomeView, height: Self.phone.height, dynamicTypeSize: .accessibility5, named: "welcome-ax5")
    }

    @Test func welcomeOnIPad() {
        assertWindowSnapshot(welcomeView, in: .portrait, backdrop: .floor, named: "welcome-ipad-portrait")
        assertWindowSnapshot(welcomeView, in: .landscape, backdrop: .floor, named: "welcome-ipad-landscape")
    }

    // MARK: Steps

    @Test func nameStep() {
        assertSnapshot(OnboardingNameStep(model: model(name: "Lily")), named: "name")
        assertSnapshot(
            OnboardingNameStep(model: model(name: "Lily Rose Margaret Ann")), named: "name-too-long")
    }

    @Test func privacyStep() {
        assertSnapshot(OnboardingPrivacyStep(model: model()), named: "privacy")
        assertSnapshot(OnboardingPrivacyStep(model: model()), colorScheme: .dark, named: "privacy-dark")
    }

    @Test func fitStep() {
        assertSnapshot(OnboardingFitStep(model: model(fit: .comfortable)), named: "fit")
    }

    @Test func closetStep() {
        assertSnapshot(OnboardingClosetStep(model: model()), named: "closet-sample")
        assertSnapshot(
            OnboardingClosetStep(model: model(closet: .empty)), colorScheme: .dark, named: "closet-empty-dark")
    }

    @Test func stepsAX5() {
        assertSnapshot(
            OnboardingNameStep(model: model(name: "Lily")), dynamicTypeSize: .accessibility5,
            named: "name-ax5")
        assertSnapshot(
            OnboardingPrivacyStep(model: model()), dynamicTypeSize: .accessibility5, named: "privacy-ax5")
    }

    @Test func privacyStepOnIPad() {
        assertWindowSnapshot(
            OnboardingPrivacyStep(model: model()), in: .landscape, backdrop: .floor, named: "privacy-ipad-landscape")
    }

    // MARK: Drawing

    /// Draws `view` `width` points wide: `height` tall when given (the welcome fills a screen),
    /// otherwise as tall as it needs.
    private func assertSnapshot(
        _ view: some View,
        width: CGFloat = phone.width,
        height: CGFloat? = nil,
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
            view, width: width, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, named: name,
            fileID: fileID, filePath: filePath, line: line, column: column)
        let content =
            view
            .frame(width: width, height: height)
            .fixedSize(horizontal: false, vertical: height == nil)
            .environment(\.closetIsStillImage, true)
            .environment(\.roomIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, scale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, us)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
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
