import XCTest

/// Swap a piece (Phase 11, LR-07, LR-08) from Your looks: swap a piece and save the changed
/// look, See all, and Remove this piece with Undo. The ranking, paging and Undo stack are covered
/// by the package tests; these check the real screens and their navigation.
final class SwapTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// Swap the shoes in Simple, see them marked Swapped, and save the changed look.
    @MainActor
    func testSwapAPieceInResultsAndSave() {
        let app = launch("demo")
        openSwap(in: app)

        // It opens on the top, with the line that says what the options are (LR-07).
        XCTAssertTrue(app.buttons["swap.piece.top"].isSelected)
        XCTAssertEqual(element("swap.explanation", in: app).label, "Your tops that go with this look")
        // At the end of the list: the line and See all (LR-07.3), and Find one (LR-07.4).
        XCTAssertTrue(element("swap.everyOne", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.buttons["swap.findOne"].exists)

        // See all opens her tops with Closet's search; choosing one tries it in the look.
        tap("swap.seeAll", in: app)
        XCTAssertTrue(app.staticTexts["All Tops"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.searchFields["Search these pieces"].exists)
        tap("picker.garment.g-pink-blouse", in: app)
        let tagline = element("swap.tagline", in: app)
        XCTAssertTrue(waitForLabel(of: tagline, containing: "Trying Cute pink shirt"), tagline.label)
        tap("swap.keep", in: app)
        XCTAssertTrue(waitForLabel(of: tagline, containing: "Top now: Cream knit sweater"), tagline.label)

        // The shoes: try the heels, then use them.
        tap("swap.piece.shoes", in: app)
        XCTAssertFalse(app.buttons["swap.use"].isEnabled, "Nothing to use until she tries one")
        let heels = app.buttons["swap.option.g-black-heels"]
        tapOnScreen(heels, in: app)
        XCTAssertTrue(waitForSelected(heels), "The heels weren't tried")
        let use = app.buttons["swap.use"]
        XCTAssertEqual(use.label, "Use these shoes")
        tapOnScreen(use, in: app)

        // Back on Your looks, the look has the heels, marked Swapped, and keeps its version.
        XCTAssertTrue(app.navigationBars["Your looks"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(
            app.staticTexts["Black block heels, Swapped"].waitUntilExists(timeout: Self.wait),
            "The new piece isn't marked Swapped")
        XCTAssertFalse(app.staticTexts["Tan loafers"].exists)
        XCTAssertTrue(app.buttons["results.version.simple"].isSelected)

        // Save look works on the changed look.
        let save = app.buttons["results.save"]
        tap("results.save", in: app)
        XCTAssertTrue(waitForLabel(of: save, containing: "Saved"), save.label)
        tap("results.tab.saved", in: app)
        let changed = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "results.saved.", "Black block heels")
        )
        XCTAssertTrue(changed.firstMatch.waitUntilExists(timeout: Self.wait), "The changed look isn't saved")
    }

    /// Remove this piece takes the shoes out; Undo puts back exactly the look before (LR-08.2).
    /// The top can't be removed, and Swap says why.
    @MainActor
    func testRemoveAndUndoInSwap() {
        let app = launch("demo")
        openSwap(in: app)

        XCTAssertFalse(app.buttons["swap.remove"].isEnabled, "Without the top it wouldn't be a look")
        tap("swap.piece.shoes", in: app)
        XCTAssertTrue(app.buttons["swap.remove"].isEnabled)
        tap("swap.remove", in: app)

        XCTAssertTrue(app.navigationBars["Your looks"].waitUntilExists(timeout: Self.wait))
        let loafers = app.staticTexts["Tan loafers"]
        XCTAssertTrue(loafers.waitUntilGone(timeout: Self.wait), "The shoes are still in the look")
        // Undo under the pieces lasts longer than the toast, so CI can reach it.
        tap("results.undoChange", in: app)
        XCTAssertTrue(loafers.waitUntilExists(timeout: Self.wait), "Undo didn't put the shoes back")
        XCTAssertFalse(app.buttons["results.undoChange"].exists)
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

    /// From the Home laptop, Style me with the defaults, then Swap a piece on Simple.
    @MainActor
    private func openSwap(in app: XCUIApplication) {
        tap("home.laptop", in: app)
        XCTAssertTrue(app.navigationBars["Style Me"].waitUntilExists(timeout: Self.wait))
        tap("styleMe.go", in: app)
        XCTAssertTrue(app.buttons["results.version.simple"].waitUntilExists(timeout: Self.wait))
        tap("results.swap", in: app)
        XCTAssertTrue(app.navigationBars["Swap a piece"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.buttons["swap.piece.top"].waitUntilHittable(timeout: Self.wait))
    }

    /// Taps a button by identifier once it can be tapped, scrolling to find it if it's off the
    /// screen.
    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)")
        app.scrollUntilHittable(button, up: 12, down: 12)
        button.tapWhenHittable(timeout: Self.wait)
    }

    /// Taps a control that's on screen, at its centre. On CI the heels option was in view (the
    /// screen recording shows it) but XCUITest reported it not hittable, twice in a row, with its
    /// scroll view's frame as infinite, after See all's sheet had closed; another time just asking
    /// whether it was hittable failed the test ("Failed to determine hittability ... Activation
    /// point invalid"). So this doesn't ask: it scrolls the control above the floating tab bar,
    /// checks its frame is inside the window, and taps there. The test then checks the tap's
    /// effect, so a tap that misses still fails. Use these shoes, under it, gets the same.
    @MainActor
    private func tapOnScreen(
        _ control: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(control.waitUntilExists(timeout: Self.wait), "No \(control)", file: file, line: line)
        let bottom =
            app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.windows.firstMatch.frame.maxY
        for _ in 0..<6 {
            if control.frame.maxY <= bottom { break }
            app.dragPage(up: true)
        }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(
            window.contains(control.frame) && control.frame.maxY <= bottom, "\(control) is off the screen", file: file,
            line: line)
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func waitForSelected(_ element: XCUIElement) -> Bool {
        return element.waitUntil(NSPredicate(format: "selected == true"), timeout: Self.wait)
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
