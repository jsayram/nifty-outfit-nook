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

/// Styling access and the paywall (Phase 30a), compared with the PNGs in
/// `__Snapshots__/StylingAccessSnapshotTests`. Drawn 402 points wide (iPhone 17) at full height:
/// - Not subscribed, with the free month (light) and at AX5.
/// - In the free month (dark).
/// - A billing grace period, and an ended subscription with the price-only offer.
@MainActor
@Suite(.heavyMainActorWork)
struct StylingAccessSnapshotTests {
    static let width: CGFloat = 402
    private let us = Locale(identifier: "en_US")
    private let product = SubscriptionProducts.monthly

    private func page(_ status: SubscriptionStatus, offer: SubscriptionOffer? = .sample) -> some View {
        let model = StylingAccessModel(now: { TestTime.now })
        model.show(status: status, offer: offer)
        return StylingAccessPage(model: model)
    }

    private var notSubscribed: some View { page(.none(at: TestTime.now)) }

    @Test func paywall() {
        assertSnapshot(notSubscribed, named: "paywall")
    }

    @Test func paywallAX5() {
        assertSnapshot(notSubscribed, dynamicTypeSize: .accessibility5, named: "paywall-ax5")
    }

    @Test func freeMonth() {
        let status = SubscriptionStatus(
            state: .trial, productID: product, expiresAt: TestTime.day(20), willAutoRenew: true,
            checkedAt: TestTime.now)
        var offer = SubscriptionOffer.sample
        offer.freeTrial = nil
        assertSnapshot(page(status, offer: offer), colorScheme: .dark, named: "free-month-dark")
    }

    @Test func paymentProblemAndEnded() {
        var offer = SubscriptionOffer.sample
        offer.freeTrial = nil
        let grace = SubscriptionStatus(
            state: .gracePeriod, productID: product, expiresAt: TestTime.day(-1), gracePeriodEndsAt: TestTime.day(5),
            willAutoRenew: true, checkedAt: TestTime.now)
        assertSnapshot(page(grace, offer: offer), named: "grace-period")
        let ended = SubscriptionStatus(
            state: .expired, productID: product, expiresAt: TestTime.day(-10), checkedAt: TestTime.now)
        assertSnapshot(page(ended, offer: offer), named: "ended")
    }

    // MARK: Drawing

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
            .environment(\.locale, us)
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
