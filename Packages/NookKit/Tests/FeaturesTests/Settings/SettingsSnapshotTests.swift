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

/// The Phase 14b screens, compared with the PNGs in `__Snapshots__/SettingsSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars:
/// - Help with its first topic open, in light, dark and AX5.
/// - Send feedback empty, filled with the app details on (dark), with the empty-note problem,
///   after sending, and at AX5.
/// - Privacy and terms in light, dark and AX5.
/// - Accessibility at the default size, and at AX5 in dark with VoiceOver and Reduce Motion on.
/// - Delete my data with counts, after a deletion that didn't finish (dark), and at AX5.
@MainActor
@Suite(.heavyMainActorWork)
struct SettingsSnapshotTests {
    static let width: CGFloat = 402
    private let us = Locale(identifier: "en_US")
    private let details = FeedbackDiagnostics(
        appVersion: "0.1", build: "1", systemVersion: "26.5", deviceModel: "iPhone13,2")

    // MARK: Help

    private var help: some View {
        HelpPage(open: [HelpContent.topics[0].id], version: AppVersion(version: "0.1", build: "1"))
    }

    @Test func helpScreen() {
        assertSnapshot(help, named: "help")
        assertSnapshot(help, colorScheme: .dark, named: "help-dark")
    }

    @Test func helpAX5() {
        assertSnapshot(help, dynamicTypeSize: .accessibility5, scale: 1, named: "help-ax5")
    }

    // MARK: Send feedback

    private func feedback(
        message: String = "", kind: FeedbackKind = .somethingWrong, details includesDetails: Bool = false,
        send: Bool = false, sent: Bool = false
    ) -> some View {
        let model = FeedbackModel(diagnostics: details)
        model.kind = kind
        model.message = message
        model.includesDetails = includesDetails
        if send || sent { model.send() }
        if sent { model.shareFinished(completed: true) }
        return FeedbackHost(model: model)
    }

    @Test func feedbackScreen() {
        assertSnapshot(feedback(), named: "feedback-empty")
        assertSnapshot(
            feedback(message: "Could the hamper show what's in the wash?", kind: .idea, details: true),
            colorScheme: .dark, named: "feedback-filled-dark")
    }

    @Test func feedbackProblemAndSent() {
        assertSnapshot(feedback(send: true), named: "feedback-problem")
        assertSnapshot(
            feedback(message: "The hamper didn't open Laundry.", sent: true), named: "feedback-sent")
    }

    @Test func feedbackAX5() {
        assertSnapshot(
            feedback(message: "Love the room.", kind: .other), dynamicTypeSize: .accessibility5, scale: 1,
            named: "feedback-ax5")
    }

    // MARK: Privacy and terms

    @Test func privacyScreen() {
        assertSnapshot(PrivacyPage(), named: "privacy")
        assertSnapshot(PrivacyPage(), colorScheme: .dark, named: "privacy-dark")
    }

    @Test func privacyAX5() {
        assertSnapshot(PrivacyPage(), dynamicTypeSize: .accessibility5, scale: 1, named: "privacy-ax5")
    }

    // MARK: Accessibility

    @Test func accessibilityScreen() {
        assertSnapshot(AccessibilityPage(), named: "accessibility")
        assertSnapshot(
            AccessibilityPage(voiceOverOverride: true, reduceMotionOverride: true),
            colorScheme: .dark, dynamicTypeSize: .accessibility5, scale: 1, named: "accessibility-ax5-dark")
    }

    // MARK: Delete my data

    private func deleteData(_ phase: DeleteDataModel.Phase = .ready) -> DeleteDataPage {
        let model = DeleteDataModel()
        model.show(
            DeleteDataModel.Counts(pieces: 21, looks: 6, pictures: 3, suitcases: 6, drafts: 1), phase: phase)
        return DeleteDataPage(model: model)
    }

    @Test func deleteDataScreen() {
        assertSnapshot(deleteData(), named: "delete-data")
        let report = DeletionReport(
            scope: .thisDevice,
            results: [(.drafts, .deleted), (.pictures, .failed), (.looks, .deleted), (.closet, .deleted)])
        assertSnapshot(deleteData(.incomplete(report)), colorScheme: .dark, named: "delete-data-incomplete-dark")
    }

    @Test func deleteDataAX5() {
        assertSnapshot(deleteData(), dynamicTypeSize: .accessibility5, scale: 1, named: "delete-data-ax5")
    }

    // MARK: Drawing

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
            .environment(\.locale, us)
            .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: content)
        // Very tall pages at AX5 come back empty at 2x (playbook, Phase 7b), so they're drawn at 1x.
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

/// Send feedback's page with the focus state it needs.
private struct FeedbackHost: View {
    let model: FeedbackModel
    @AccessibilityFocusState private var focus: FeedbackField?

    var body: some View {
        FeedbackPage(model: model, focus: $focus)
    }
}
