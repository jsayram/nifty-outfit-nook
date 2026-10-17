import XCTest

/// Your looks (Phase 10b, LR-05a, LR-05b, LR-06): a full styling run from the Home laptop, and
/// the states forced with fixture flags. The words, rules and every state's layout are covered by
/// the package and snapshot tests; these check the real screen, its navigation and its buttons.
final class YourLooksTests: XCTestCase {
    static let wait = uiTestWait

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
        XCTAssertTrue(simple.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(simple.isSelected)
        let description = element("results.versionDescription", in: app)
        XCTAssertEqual(description.label, "Easy and safe")

        select("results.version.dressedUp", in: app)
        XCTAssertTrue(waitForLabel(of: description, containing: "a little classier"), description.label)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "Same as Simple")).firstMatch.exists)

        // Something new adds one piece she doesn't own, with Find one (LR-05b.1).
        select("results.version.somethingNew", in: app)
        XCTAssertTrue(waitForLabel(of: description, containing: "plus one piece you don’t have"), description.label)
        let findOne = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lookPieces.findOne."))
        XCTAssertEqual(findOne.count, 1)

        // Save look: the button says Saved, and the look is on the Saved tab.
        // A second tap would unsave it, so it's tapped again only if the label didn't change.
        let save = app.buttons["results.save"]
        tap("results.save", in: app) { save.exists && save.label.contains("Saved") }
        select("results.tab.saved", in: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "results.saved.r-"))
        XCTAssertTrue(saved.firstMatch.waitUntilExists(timeout: Self.wait), "The saved look isn't on the Saved tab")
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved.firstMatch.label.contains("something new"), saved.firstMatch.label)
        // The demo's two saved Office looks are there too.
        XCTAssertTrue(app.buttons["results.saved.o-interview"].exists)

        // Back on Today, Try it on says what it will do and makes nothing until asked (RD-06.2;
        // making a picture is in SavedLooksTests).
        select("results.tab.today", in: app)
        tap("results.tryOn", in: app, showing: element("tryOn.ready", in: app))
        app.buttons["Close"].tapUntilGone(timeout: Self.wait)
        // Swap a piece opens Swap (Phase 11); Back leaves the look as it was.
        tap("results.swap", in: app, showing: app.navigationBars["Swap a piece"])
        app.goBack(from: "Swap a piece", to: "Your looks", timeout: Self.wait)

        // Try a different outfit: a new look replaces all three versions (LR-05a.4), back on
        // Simple, and the saved one stays on the Saved tab.
        let bundles = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "lookBundle."))
        let first = bundles.firstMatch.identifier
        let replaced = NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "lookBundle.r-", first)
        tap("results.tryDifferent", in: app) {
            bundles.firstMatch.exists && replaced.evaluate(with: bundles.firstMatch)
        }
        XCTAssertTrue(app.buttons["results.version.simple"].isSelected)
        XCTAssertTrue(waitForLabel(of: save, containing: "Save look"), save.label)
        select("results.tab.saved", in: app)
        XCTAssertEqual(saved.count, 1)
    }

    /// `stylist-waits`: Your looks shows its styling state, and Cancel goes back to Style Me.
    @MainActor
    func testStylingCanBeCancelled() {
        let app = launch("demo:stylist-waits")
        styleMe(in: app, waitForResult: false)
        XCTAssertTrue(element("results.styling", in: app).waitUntilExists(timeout: Self.wait))
        leaveYourLooks(with: "results.cancel", in: app)
        XCTAssertTrue(app.buttons["styleMe.go"].isEnabled)
    }

    /// `offline-once`: offline, then Retry once the connection is back.
    @MainActor
    func testOfflineThenRetry() {
        let app = launch("demo:offline-once")
        styleMe(in: app, waitForResult: false)
        XCTAssertTrue(app.staticTexts["Styling needs a connection"].waitUntilExists(timeout: Self.wait))
        // The Saved tab works offline.
        tap("results.seeSaved", in: app, showing: app.buttons["results.saved.o-interview"])
        select("results.tab.today", in: app)
        app.buttons["Retry"].tapUntil(app.buttons["results.version.simple"], appears: Self.wait)
    }

    /// The other states, each forced by its flag: partial, insufficient and didn't finish.
    @MainActor
    func testEachStateByFlag() {
        let partial = launch("demo:stylist-partial")
        styleMe(in: partial, waitForResult: false)
        XCTAssertTrue(partial.buttons["results.version.dressedUp"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(partial.buttons["results.version.somethingNew"].exists)
        XCTAssertTrue(
            partial.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No Something new this time"))
                .firstMatch.exists)
        partial.terminate()

        let insufficient = launch("demo:stylist-insufficient")
        styleMe(in: insufficient, waitForResult: false)
        XCTAssertTrue(element("results.insufficient", in: insufficient).waitUntilExists(timeout: Self.wait))
        leaveYourLooks(with: "results.changeRequest", in: insufficient)
        insufficient.terminate()

        let failing = launch("demo:stylist-fails")
        styleMe(in: failing, waitForResult: false)
        XCTAssertTrue(failing.staticTexts["Styling didn’t finish"].waitUntilExists(timeout: Self.wait))
        leaveYourLooks(with: "results.backToStyleMe", in: failing)
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", fixtures]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        return app
    }

    /// From the Home laptop, Style me with the defaults (Office, Main closet).
    @MainActor
    private func styleMe(in app: XCUIApplication, waitForResult: Bool = true) {
        tap("home.laptop", in: app, showing: app.navigationBars["Style Me"])
        tap("styleMe.go", in: app, showing: app.navigationBars["Your looks"])
        if waitForResult {
            XCTAssertTrue(app.buttons["results.version.simple"].waitUntilExists(timeout: Self.wait))
        }
    }

    /// Taps a button that goes back from Your looks to Style Me, and waits for Your looks to go.
    /// Style Me's bar is there while Your looks is still sliding away.
    @MainActor
    private func leaveYourLooks(with identifier: String, in app: XCUIApplication) {
        let yourLooks = app.navigationBars["Your looks"]
        tap(identifier, in: app) { !yourLooks.exists }
        XCTAssertTrue(app.navigationBars["Style Me"].waitUntilExists(timeout: Self.wait))
    }

    /// Taps a version or tab until it says it's selected.
    @MainActor
    private func select(
        _ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let button = app.buttons[identifier]
        tap(identifier, in: app, file: file, line: line) { button.exists && button.isSelected }
    }

    /// Taps a button by identifier, scrolling to find it if it's off the screen, until `effect`
    /// holds (see `XCUIElement.tapUntil(timeout:_:)`).
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)", file: file, line: line)
        app.scrollUntilHittable(button, up: 12, down: 12)
        button.tapUntil(timeout: Self.wait, else: "\(identifier) didn't do its job", file: file, line: line, effect)
    }

    /// Taps a button by identifier until `next` appears.
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, showing next: XCUIElement, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tap(identifier, in: app, file: file, line: line) { next.exists }
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        return element.waitUntil(NSPredicate(format: "label CONTAINS %@", text), timeout: Self.wait)
    }
}
