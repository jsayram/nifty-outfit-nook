import XCTest

/// The cloud stylist (Phase 27a) on the real screens, against the in-process fake backend
/// (`-cloud-stylist`): consent first, then looks made of her own pieces with the stylist's why
/// line, the same request again from her history, Not now, and a provider that fails. The rules
/// behind each are `CloudStylistTests` and `YourLooksCloudTests` in the package, and the
/// backend's own tests.
final class CloudStylistTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testConsentThenLooksWithAWhyLineThenTheSameRequestFromHistory() {
        let app = launch(stylist: "normal")
        styleMe(in: app)

        // Nothing is sent before she says yes: Quick ideas made on the phone, with Review.
        let quickIdeas = app.descendants(matching: .any)["results.quickIdeas"]
        XCTAssertTrue(quickIdeas.waitUntilExists(timeout: Self.wait))
        keepScreenshot("27a-1-needs-consent")
        tap(app.buttons["Review"], until: { app.buttons["stylistConsent.allow"].exists })
        keepScreenshot("27a-2-consent-sheet")
        tap(app.buttons["stylistConsent.allow"], until: { !quickIdeas.exists })
        XCTAssertTrue(app.buttons["results.version.simple"].waitUntilExists(timeout: Self.wait))

        // Looks from the stylist, with its why line under the look.
        let why = app.staticTexts["results.why"]
        XCTAssertTrue(why.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(why.label.hasPrefix("Why:"), why.label)
        keepScreenshot("27a-3-looks-with-why")

        // The same request again: from her history, nothing sent, and New ideas to ask afresh.
        let yourLooks = app.navigationBars["Your looks"]
        app.goBack(from: "Your looks", to: "Style Me", timeout: Self.wait)
        XCTAssertFalse(yourLooks.exists)
        tap(app.buttons["styleMe.go"], until: { app.buttons["results.version.simple"].exists })
        let history = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "From your history"))
        XCTAssertTrue(history.firstMatch.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(app.buttons["results.tryDifferent"].label, "New ideas")
        keepScreenshot("27a-4-from-history", showing: app.buttons["results.tryDifferent"])
    }

    @MainActor
    func testNotNowSendsNothingAndAFailingProviderIsACalmRetry() {
        let app = launch(stylist: "fails")
        styleMe(in: app)
        let quickIdeas = app.descendants(matching: .any)["results.quickIdeas"]
        XCTAssertTrue(quickIdeas.waitUntilExists(timeout: Self.wait))
        tap(app.buttons["Review"], until: { app.buttons["stylistConsent.notNow"].exists })
        tap(app.buttons["stylistConsent.notNow"], until: { !app.buttons["stylistConsent.notNow"].exists })
        XCTAssertTrue(quickIdeas.exists)

        // The provider fails: Quick ideas again, saying so, with Ask the stylist to try again.
        tap(app.buttons["Review"], until: { app.buttons["stylistConsent.allow"].exists })
        tap(app.buttons["stylistConsent.allow"], until: { app.buttons["Ask the stylist"].exists })
        XCTAssertTrue(quickIdeas.exists)
        keepScreenshot("27a-5-provider-failed")
    }

    /// The Phase 28 checkpoint: with her consent off and the phone offline, Style Me still gives
    /// Quick ideas made of her own pieces, dressed for the rainy day, and sends nothing.
    @MainActor
    func testOfflineWithoutConsentStillGivesQuickIdeas() {
        let app = launch(stylist: "normal", extra: ["-connection", "offline"])
        styleMe(in: app)
        let quickIdeas = app.descendants(matching: .any)["results.quickIdeas"]
        XCTAssertTrue(quickIdeas.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(quickIdeas.label, "Quick ideas (on your phone)")
        let why = app.staticTexts["results.why"]
        XCTAssertTrue(why.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(why.label.contains("wet weather"), why.label)
        keepScreenshot("28-1-quick-ideas-offline")
        tap(app.buttons["results.version.dressedUp"], until: { app.buttons["results.version.dressedUp"].isSelected })
        keepScreenshot("28-2-dressed-up")
    }

    /// F1c: the server's record shows no styling access (403 entitlement_required). Your looks
    /// says so and offers Styling access instead of a plain "not allowed".
    @MainActor
    func testNoStylingAccessOnTheServerOffersStylingAccess() {
        let app = launch(stylist: "noStylingAccess")
        styleMe(in: app)
        tap(app.buttons["Review"], until: { app.buttons["stylistConsent.allow"].exists })
        let see = app.buttons["See styling access"]
        tap(app.buttons["stylistConsent.allow"], until: { see.exists })
        keepScreenshot("f1c-no-styling-access")
        tap(see, until: { app.navigationBars["Styling access"].exists })
    }

    // MARK: Helpers

    @MainActor
    private func launch(stylist: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo", "-cloud-stylist", stylist] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        return app
    }

    /// From the Home laptop, Style me with the defaults (Office, Main closet).
    @MainActor
    private func styleMe(in app: XCUIApplication) {
        tap(app.buttons["home.laptop"], until: { app.navigationBars["Style Me"].exists })
        tap(app.buttons["styleMe.go"], until: { app.navigationBars["Your looks"].exists })
    }

    @MainActor
    private func tap(
        _ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(button)", file: file, line: line)
        XCUIApplication().scrollUntilHittable(button, up: 12, down: 12)
        button.tapUntil(timeout: Self.wait, else: "\(button) didn't do its job", file: file, line: line, effect)
    }

    @MainActor
    private func keepScreenshot(_ name: String, showing element: XCUIElement? = nil) {
        if let element {
            XCUIApplication().scrollUntilHittable(element, up: 12, down: 12)
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
