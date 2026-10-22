import XCTest

/// Styling access and the paywall (Phase 30a), on a scripted subscription (`-subscription`), so
/// nothing reaches the App Store: Profile's row, the offer with the free month's terms, Start free
/// month, and the status afterwards. Buying through StoreKit itself is `SubscriptionStoreKitTests`
/// (the hosted unit tests), on Xcode's local StoreKit testing.
final class StylingAccessTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStartTheFreeMonthFromProfile() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-subscription", "none"]
        app.launch()
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        let row = app.buttons["profile.stylingAccess"]
        app.reveal(row, timeout: Self.wait)
        XCTAssertTrue(row.label.contains("Not subscribed"), "Profile's row says \(row.label)")
        row.tapUntil(app.navigationBars["Styling access"], appears: Self.wait)

        // The terms before buying: the price, the free month, and how it renews.
        let terms = element("access.offerTerms", in: app)
        XCTAssertTrue(terms.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(terms.label.contains("1 month free, then $9.99 a month."), "Offer: \(terms.label)")
        XCTAssertTrue(terms.label.contains("renews automatically"))
        XCTAssertTrue(element("access.restore", in: app).exists)
        XCTAssertTrue(element("access.terms", in: app).exists)
        XCTAssertTrue(element("access.privacy", in: app).exists)
        XCTAssertFalse(element("access.manage", in: app).exists)
        keepScreenshot("paywall")

        let subscribe = element("access.subscribe", in: app)
        app.reveal(subscribe, timeout: Self.wait)
        subscribe.tapUntil(element("access.message", in: app), appears: Self.wait)
        XCTAssertTrue(labelled("Styling access is on.", in: app).exists)
        XCTAssertTrue(labelled("Your free month ends", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(element("access.manage", in: app).exists)
        XCTAssertFalse(element("access.subscribe", in: app).exists)
        keepScreenshot("free-month")
    }

    @MainActor
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
}
