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
        tap("swap.seeAll", in: app, showing: app.staticTexts["All Tops"])
        XCTAssertTrue(app.searchFields["Search these pieces"].exists)
        let tagline = element("swap.tagline", in: app)
        tap("picker.garment.g-pink-blouse", in: app) { self.label(of: tagline, contains: "Trying Cute pink shirt") }
        tap("swap.keep", in: app) { self.label(of: tagline, contains: "Top now: Cream knit sweater") }

        // The shoes: try the heels, then use them.
        let shoes = app.buttons["swap.piece.shoes"]
        tap("swap.piece.shoes", in: app) { shoes.exists && shoes.isSelected }
        XCTAssertFalse(app.buttons["swap.use"].isEnabled, "Nothing to use until she tries one")
        let heels = app.buttons["swap.option.g-black-heels"]
        tapOnScreen(heels, in: app, else: "The heels weren't tried") { heels.exists && heels.isSelected }
        let use = app.buttons["swap.use"]
        XCTAssertEqual(use.label, "Use these shoes")
        // Back on Your looks once Swap a piece has gone.
        let swapBar = app.navigationBars["Swap a piece"]
        tapOnScreen(use, in: app, else: "Swap a piece didn't close") { !swapBar.exists }

        // Back on Your looks, the look has the heels, marked Swapped, and keeps its version.
        XCTAssertTrue(app.navigationBars["Your looks"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(
            app.staticTexts["Black block heels, Swapped"].waitUntilExists(timeout: Self.wait),
            "The new piece isn't marked Swapped")
        XCTAssertFalse(app.staticTexts["Tan loafers"].exists)
        XCTAssertTrue(app.buttons["results.version.simple"].isSelected)

        // Save look works on the changed look.
        // A second tap would unsave it, so it's tapped again only if the label didn't change.
        let save = app.buttons["results.save"]
        tap("results.save", in: app) { self.label(of: save, contains: "Saved") }
        let savedTab = app.buttons["results.tab.saved"]
        tap("results.tab.saved", in: app) { savedTab.exists && savedTab.isSelected }
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
        let shoes = app.buttons["swap.piece.shoes"]
        tap("swap.piece.shoes", in: app) { shoes.exists && shoes.isSelected }
        XCTAssertTrue(app.buttons["swap.remove"].isEnabled)
        let swapBar = app.navigationBars["Swap a piece"]
        tap("swap.remove", in: app) { !swapBar.exists }

        XCTAssertTrue(app.navigationBars["Your looks"].waitUntilExists(timeout: Self.wait))
        let loafers = app.staticTexts["Tan loafers"]
        XCTAssertTrue(loafers.waitUntilGone(timeout: Self.wait), "The shoes are still in the look")
        // Undo under the pieces lasts longer than the toast, so CI can reach it.
        tap("results.undoChange", in: app, showing: loafers)
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
        tap("home.laptop", in: app, showing: app.navigationBars["Style Me"])
        tap("styleMe.go", in: app, showing: app.buttons["results.version.simple"])
        tap("results.swap", in: app, showing: app.navigationBars["Swap a piece"])
        XCTAssertTrue(app.buttons["swap.piece.top"].waitUntilHittable(timeout: Self.wait))
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

    /// Taps a control that's on screen, at its centre. On CI the heels option was in view (the
    /// screen recording shows it) but XCUITest reported it not hittable, twice in a row, with its
    /// scroll view's frame as infinite, after See all's sheet had closed; another time just asking
    /// whether it was hittable failed the test ("Failed to determine hittability ... Activation
    /// point invalid"). So this doesn't ask: it scrolls the control above the floating tab bar,
    /// checks its frame is inside the window, and taps there. The test then checks the tap's
    /// effect, and taps once more if it didn't come, so a tap that misses still fails. Use these
    /// shoes, under it, gets the same.
    @MainActor
    private func tapOnScreen(
        _ control: XCUIElement, in app: XCUIApplication, else message: String, file: StaticString = #filePath,
        line: UInt = #line, until effect: @escaping @MainActor () -> Bool
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
        let centre = control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(centre.tapUntil(timeout: Self.wait, effect), message, file: file, line: line)
    }

    /// Whether the element is there and its label contains `text`.
    @MainActor
    private func label(of element: XCUIElement, contains text: String) -> Bool {
        element.exists && element.label.contains(text)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
