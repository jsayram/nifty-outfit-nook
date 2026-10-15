import XCTest

/// Your looks (Phase 10b, LR-05a, LR-05b, LR-06): a full styling run from the Home laptop, and
/// the states forced with fixture flags. The words, rules and every state's layout are covered by
/// the package and snapshot tests; these check the real screen, its navigation and its buttons.
final class YourLooksTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// Laptop, request, results, each version, save, the look on the Saved tab, the stand-ins,
    /// and Try a different outfit.
    @MainActor
    func testAFullStylingRun() {
        let app = launch("demo")
        styleMe(in: app)

        // Three versions on one line, Simple first (LR-05a).
        let simple = app.buttons["results.version.simple"]
        XCTAssertTrue(simple.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(simple.isSelected)
        let description = element("results.versionDescription", in: app)
        XCTAssertEqual(description.label, "Easy and safe")

        tap("results.version.dressedUp", in: app)
        XCTAssertTrue(app.buttons["results.version.dressedUp"].isSelected)
        XCTAssertTrue(waitForLabel(of: description, containing: "a little classier"), description.label)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "Same as Simple")).firstMatch.exists)

        // Something new adds one piece she doesn't own, with Find one (LR-05b.1).
        tap("results.version.somethingNew", in: app)
        XCTAssertTrue(waitForLabel(of: description, containing: "plus one piece you don’t have"), description.label)
        let findOne = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lookPieces.findOne."))
        XCTAssertEqual(findOne.count, 1)

        // Save look: the button says Saved, and the look is on the Saved tab.
        let save = app.buttons["results.save"]
        tap("results.save", in: app)
        XCTAssertTrue(waitForLabel(of: save, containing: "Saved"), save.label)
        tap("results.tab.saved", in: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "results.saved.r-"))
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: Self.wait), "The saved look isn't on the Saved tab")
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved.firstMatch.label.contains("something new"), saved.firstMatch.label)
        // The demo's two saved Office looks are there too.
        XCTAssertTrue(app.buttons["results.saved.o-interview"].exists)

        // Back on Today, the stand-ins open without sending anything.
        tap("results.tab.today", in: app)
        tap("results.tryOn", in: app)
        XCTAssertTrue(element("results.stub.tryOn", in: app).waitForExistence(timeout: Self.wait))
        app.buttons["Close"].tap()
        // Swap a piece opens Swap (Phase 11); Back leaves the look as it was.
        tap("results.swap", in: app)
        XCTAssertTrue(app.navigationBars["Swap a piece"].waitForExistence(timeout: Self.wait))
        app.goBack(from: "Swap a piece", to: "Your looks", timeout: Self.wait)

        // Try a different outfit: a new look replaces all three versions (LR-05a.4), back on
        // Simple, and the saved one stays on the Saved tab.
        let bundles = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "lookBundle."))
        let first = bundles.firstMatch.identifier
        tap("results.tryDifferent", in: app)
        let replaced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "lookBundle.r-", first),
            object: bundles.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [replaced], timeout: Self.wait), .completed, "The look wasn't replaced")
        XCTAssertTrue(app.buttons["results.version.simple"].isSelected)
        XCTAssertTrue(waitForLabel(of: save, containing: "Save look"), save.label)
        tap("results.tab.saved", in: app)
        XCTAssertEqual(saved.count, 1)
    }

    /// `stylist-waits`: Your looks shows its styling state, and Cancel goes back to Style Me.
    @MainActor
    func testStylingCanBeCancelled() {
        let app = launch("demo:stylist-waits")
        styleMe(in: app, waitForResult: false)
        XCTAssertTrue(element("results.styling", in: app).waitForExistence(timeout: Self.wait))
        tap("results.cancel", in: app)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["styleMe.go"].isEnabled)
    }

    /// `offline-once`: offline, then Retry once the connection is back.
    @MainActor
    func testOfflineThenRetry() {
        let app = launch("demo:offline-once")
        styleMe(in: app, waitForResult: false)
        XCTAssertTrue(app.staticTexts["Styling needs a connection"].waitForExistence(timeout: Self.wait))
        // The Saved tab works offline.
        tap("results.seeSaved", in: app)
        XCTAssertTrue(app.buttons["results.saved.o-interview"].waitForExistence(timeout: Self.wait))
        tap("results.tab.today", in: app)
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.buttons["results.version.simple"].waitForExistence(timeout: Self.wait))
    }

    /// The other states, each forced by its flag: partial, insufficient and didn't finish.
    @MainActor
    func testEachStateByFlag() {
        let partial = launch("demo:stylist-partial")
        styleMe(in: partial, waitForResult: false)
        XCTAssertTrue(partial.buttons["results.version.dressedUp"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(partial.buttons["results.version.somethingNew"].exists)
        XCTAssertTrue(
            partial.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No Something new this time"))
                .firstMatch.exists)
        partial.terminate()

        let insufficient = launch("demo:stylist-insufficient")
        styleMe(in: insufficient, waitForResult: false)
        XCTAssertTrue(element("results.insufficient", in: insufficient).waitForExistence(timeout: Self.wait))
        tap("results.changeRequest", in: insufficient)
        XCTAssertTrue(insufficient.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        insufficient.terminate()

        let failing = launch("demo:stylist-fails")
        styleMe(in: failing, waitForResult: false)
        XCTAssertTrue(failing.staticTexts["Styling didn’t finish"].waitForExistence(timeout: Self.wait))
        tap("results.backToStyleMe", in: failing)
        XCTAssertTrue(failing.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", fixtures]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: Self.wait))
        return app
    }

    /// From the Home laptop, Style me with the defaults (Office, Main closet).
    @MainActor
    private func styleMe(in app: XCUIApplication, waitForResult: Bool = true) {
        tap("home.laptop", in: app)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        tap("styleMe.go", in: app)
        XCTAssertTrue(app.navigationBars["Your looks"].waitForExistence(timeout: Self.wait))
        if waitForResult {
            XCTAssertTrue(app.buttons["results.version.simple"].waitForExistence(timeout: Self.wait))
        }
    }

    /// Taps a button by identifier, scrolling to find it if it's off the screen.
    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "No button \(identifier)")
        var swipes = 0
        while !button.isHittable && swipes < 6 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        while !button.isHittable && swipes < 12 {
            app.swipeDown(velocity: .slow)
            swipes += 1
        }
        button.tap()
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [changed], timeout: Self.wait) == .completed
    }
}
