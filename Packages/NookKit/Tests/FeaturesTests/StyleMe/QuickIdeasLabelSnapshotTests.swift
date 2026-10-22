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

/// Phase 28: the label that says the looks were made on the phone, and why, compared with the
/// PNGs in `__Snapshots__/QuickIdeasLabelSnapshotTests`. Each reason, the on-device title, dark
/// and AX5, and Your looks with Quick ideas from the demo closet when she hasn't given consent.
@MainActor
@Suite(.heavyMainActorWork)
struct QuickIdeasLabelSnapshotTests {
    static let width: CGFloat = 402

    private func label(
        _ reason: QuickIdeasReason?, lane: StylistLane = .rules, connection: ConnectionState = .online
    ) -> some View {
        QuickIdeasLabel(lane: lane, reason: reason, retry: {}, reviewConsent: {})
            .padding(NookSpacing.medium)
            .background(Color.nook.wallGradient)
            .environment(\.connection, ConnectionStatus(connection))
    }

    @Test func needsConsent() {
        assertSnapshot(label(.needsConsent), named: "needs-consent")
    }

    @Test func offline() {
        assertSnapshot(label(.offline, connection: .offline), named: "offline")
    }

    @Test func paused() {
        assertSnapshot(label(.limited(.paused(feature: .style, retryAfterSeconds: nil))), named: "paused")
    }

    @Test func cloudDidNotFinish() {
        assertSnapshot(label(.cloudDidNotFinish), named: "did-not-finish")
    }

    @Test func noBackend() {
        assertSnapshot(label(nil), named: "no-backend")
    }

    @Test func onDevice() {
        assertSnapshot(label(.offline, lane: .onDevice, connection: .offline), named: "on-device")
    }

    @Test func needsConsentDark() {
        assertSnapshot(label(.needsConsent), colorScheme: .dark, named: "needs-consent-dark")
    }

    @Test func needsConsentAX5() {
        assertSnapshot(label(.needsConsent), dynamicTypeSize: .accessibility5, named: "needs-consent-ax5")
    }

    /// Your looks without consent: Quick ideas from the demo closet, with the label and why line.
    @Test func yourLooksWithQuickIdeas() async {
        var services = yourLooksServices()
        services.cloudStyling = true
        services.stylistConsent = InMemoryStylistConsentStore(nil)
        let model = await styledLooks(services: services)
        assertSnapshot(YourLooksPage(model: model), named: "your-looks")
    }

    private func assertSnapshot(
        _ view: some View,
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
            view, width: Self.width, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, named: name,
            fileID: fileID, filePath: filePath, line: line, column: column)
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
        let renderer = ImageRenderer(content: content.snapshotPhotos())
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
