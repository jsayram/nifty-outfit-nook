import XCTest

/// Suitcases and Laundry (Phase 13): packing a suitcase and styling from it, and marking pieces
/// dirty and clean with the hamper on Home following along. The rules and words are covered by
/// the package tests; these check the real screens, sheets and navigation.
final class SuitcasesAndLaundryTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// LR-17, RD-09.2, FR-67: "+ Add a suitcase", pack three pieces, take one out and Undo, then
    /// Style me from this suitcase. Sending the request remembers it, so Home's suitcase shows it.
    @MainActor
    func testPackASuitcaseAndStyleFromIt() {
        let app = launch("demo")
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        tap("closet.suitcases", in: app)
        XCTAssertTrue(app.navigationBars["Suitcases"].waitForExistence(timeout: Self.wait))

        // "+ Add a suitcase" is in the bar, whatever is below (LR-17.1).
        app.buttons["suitcases.add"].tapWhenHittable(timeout: Self.wait)
        let name = app.textFields["field.suitcaseEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))
        name.tap()
        name.typeText("Beach week")
        app.buttons["suitcaseEditor.icon.backpack"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.buttons["suitcaseEditor.icon.backpack"].isSelected)
        app.buttons["suitcaseEditor.save"].tapWhenHittable(timeout: Self.wait)

        // The new suitcase opens on the packing sheet.
        XCTAssertTrue(app.navigationBars["Beach week"].waitForExistence(timeout: Self.wait))
        let count = element("packing.count", in: app)
        XCTAssertTrue(count.waitForExistence(timeout: Self.wait), "The packing sheet didn't open")
        XCTAssertTrue(count.label.hasPrefix("Nothing packed yet"), count.label)
        for (search, id) in [("navy pants", "g-navy-trousers"), ("pink", "g-pink-blouse"), ("flats", "g-nude-flats")] {
            let field = app.searchFields["Search your closet"]
            XCTAssertTrue(field.waitForExistence(timeout: Self.wait))
            // Empties the last search before typing the next.
            let clear = app.buttons["Clear search"]
            if clear.exists { clear.tap() }
            field.tap()
            field.typeText("\(search)\n")
            let piece = app.buttons["packing.garment.\(id)"]
            piece.tapWhenHittable(timeout: Self.wait)
            XCTAssertTrue(waitUntilSelected(piece), "\(id) wasn't packed")
        }
        XCTAssertTrue(waitForLabel(of: count, containing: "3 packed"), count.label)
        app.buttons["Close"].tapUntilGone(timeout: Self.wait)

        // The three pieces are on the suitcase. One comes out, and Undo puts it back.
        XCTAssertTrue(waitForLabel(of: element("suitcase.count", in: app), containing: "3 pieces"))
        app.buttons["suitcase.garment.g-pink-blouse.remove"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: element("suitcase.count", in: app), containing: "2 pieces"))
        app.buttons["Undo"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: element("suitcase.count", in: app), containing: "3 pieces"))

        // Style me from this suitcase opens Style Me with it as the source, strict to it.
        tap("suitcase.styleMe", in: app)
        let source = app.buttons["styleMe.source"]
        XCTAssertTrue(source.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForLabel(of: source, containing: "Beach week"), source.label)
        tap("styleMe.go", in: app)
        XCTAssertTrue(app.navigationBars["Your looks"].waitForExistence(timeout: Self.wait))

        // Home's suitcase shows it now, as a favourite source (RD-01.3, RD-09.2).
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        let suitcase = app.buttons["home.suitcase"]
        XCTAssertTrue(
            waitForLabel(of: suitcase, containing: "Suitcase: Source, Beach week, 3 pieces, Suitcase only"),
            suitcase.label)

        // And it opens Suitcases on the Closet tab, where it's the chosen source.
        suitcase.tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Suitcases"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Closet"].isSelected)
        let row = app.buttons.matching(identifier: "suitcases.row.mainCloset.choose").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait))
        XCTAssertFalse(row.isSelected)
    }

    /// RD-11.3, RD-11.5, PRD §7.3: a piece marked dirty on its detail fills the hamper; Laundry
    /// cleans one with Undo, then the rest with Mark all clean, and the hamper empties.
    @MainActor
    func testMarkDirtyThenCleanInLaundry() {
        let app = launch("demo:laundry=some")
        let hamper = app.buttons["home.hamper"]
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, 2 to wash"), hamper.label)

        // Mark the navy trousers dirty on their detail.
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        let search = app.searchFields["Search your closet"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait))
        search.tap()
        search.typeText("navy pants\n")
        app.buttons["closet.garment.g-navy-trousers"].tapWhenHittable(timeout: Self.wait)
        tap("garment.laundry", in: app)
        XCTAssertTrue(labelled("Marked as dirty", in: app).waitForExistence(timeout: Self.wait))

        // Home's hamper has three now, without a relaunch.
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, 3 to wash"), hamper.label)

        // The hamper opens Laundry on the Closet tab.
        hamper.tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Laundry"].waitForExistence(timeout: Self.wait))
        let count = element("laundry.count", in: app)
        XCTAssertTrue(waitForLabel(of: count, containing: "3 pieces in the wash"), count.label)

        // Mark clean on one piece, then Undo.
        tap("laundry.markClean.g-navy-trousers", in: app)
        XCTAssertTrue(waitForLabel(of: count, containing: "2 pieces in the wash"), count.label)
        app.buttons["Undo"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: count, containing: "3 pieces in the wash"), count.label)

        // Two ticked, Clean selected asks first.
        tap("laundry.select.g-navy-trousers", in: app)
        XCTAssertTrue(app.buttons["laundry.select.g-navy-trousers"].isSelected)
        let firstOther = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'laundry.select.' AND identifier != 'laundry.select.g-navy-trousers'")
        ).firstMatch
        firstOther.tapWhenHittable(timeout: Self.wait)
        tap("laundry.cleanSelected", in: app)
        app.buttons["laundry.confirm"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: count, containing: "1 piece in the wash"), count.label)

        // Mark all clean asks too, then nothing is in the wash.
        tap("laundry.cleanAll", in: app)
        app.buttons["laundry.confirm"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(element("laundry.empty", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForLabel(of: count, containing: "Nothing in the wash"), count.label)

        // And Home's hamper is all clean.
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, All clean"), hamper.label)
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.toursOff + ["-fixtures", fixtures]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: Self.wait))
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Taps a button by identifier, scrolling up to find it if it's below the screen.
    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "No button \(identifier)")
        var swipes = 0
        while !button.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        button.tap()
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: Self.wait) == .completed
    }

    @MainActor
    private func waitUntilSelected(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: Self.wait) == .completed
    }
}
