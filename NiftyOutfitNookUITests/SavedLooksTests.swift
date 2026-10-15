import XCTest

/// Saved Looks (Phase 12a, RD-08, LR-09, LR-10): a look saved on Your looks found again by search
/// and opened, Delete look with Undo, and a frame on the Home shelf opening its look. Search, the
/// filters, renaming, Wear today's records and the swap rules are covered by the package and
/// snapshot tests; these check the real screens, their navigation and buttons.
final class SavedLooksTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// Style me, Save look, then find it on Saved Looks by its name and open it.
    @MainActor
    func testASavedLookIsFoundBySearchAndOpens() {
        let app = launch()
        tap("home.laptop", in: app)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        tap("styleMe.go", in: app)
        XCTAssertTrue(app.buttons["results.version.simple"].waitForExistence(timeout: Self.wait))
        tap("results.save", in: app)
        XCTAssertTrue(waitForLabel(of: app.buttons["results.save"], containing: "Saved"))

        // Its name, from the Saved tab's row ("Cream & navy: Cream knit sweater, …").
        tap("results.tab.saved", in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "results.saved.r-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "The saved look isn't on the Saved tab")
        let lookID = String(row.identifier.dropFirst("results.saved.".count))
        let name = String(row.label.prefix { $0 != ":" })
        XCTAssertFalse(name.isEmpty)

        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        let search = app.searchFields["Search your looks"]
        search.tapWhenHittable(timeout: Self.wait)
        search.typeText(name + "\n")
        let cell = app.buttons["savedLooks.look.\(lookID)"]
        XCTAssertTrue(cell.waitForExistence(timeout: Self.wait), "Search didn't find \(name)")
        // The demo's saved looks with other names are filtered out.
        XCTAssertTrue(app.buttons["savedLooks.look.o-lace-date"].waitForNonExistence(timeout: Self.wait))

        cell.tapWhenHittable(timeout: Self.wait)
        let title = element("lookDetail.name", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(title.label, name)
        XCTAssertTrue(element("lookDetail.facts", in: app).label.contains("Saved today"))
    }

    /// Delete look goes back to the grid without it, and Undo brings it back.
    @MainActor
    func testDeleteLookWithUndo() {
        let app = launch()
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        tap("savedLooks.look.o-lace-date", in: app)
        XCTAssertTrue(element("lookDetail.name", in: app).waitForExistence(timeout: Self.wait))
        tap("lookDetail.delete", in: app)

        let lace = app.buttons["savedLooks.look.o-lace-date"]
        XCTAssertTrue(lace.waitForNonExistence(timeout: Self.wait), "The look is still on Saved Looks")
        // The line over the looks keeps Undo after the toast has gone.
        let banner = element("savedLooks.deleted", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait))
        banner.buttons["Undo"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(lace.waitForExistence(timeout: Self.wait), "Undo didn't bring the look back")
        XCTAssertTrue(banner.waitForNonExistence(timeout: Self.wait))
    }

    /// A frame under the Home shelf opens its look on Saved Looks; Back goes to the grid. The
    /// blazer she gave away shows Swap it, which opens Swap a piece on that piece.
    @MainActor
    func testAShelfFrameOpensItsLook() {
        let app = launch()
        let frame = app.buttons["home.frame.2"]
        XCTAssertTrue(frame.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(frame.label, "Saved look: Interview navy and pink")
        frame.tapWhenHittable(timeout: Self.wait)

        let title = element("lookDetail.name", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(title.label, "Interview navy and pink")
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Saved Looks"].isSelected)
        app.goBack(from: "Interview navy and pink", to: "Saved Looks", timeout: Self.wait)
        XCTAssertTrue(app.buttons["savedLooks.look.o-interview"].waitForExistence(timeout: Self.wait))

        tap("savedLooks.look.o-blazer-office", in: app)
        tap("lookPieces.swapIt.o-blazer-office-g-gray-blazer", in: app)
        XCTAssertTrue(app.navigationBars["Swap a piece"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["swap.piece.layer"].isSelected)
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", "demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: Self.wait))
        return app
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
        button.tapWhenHittable(timeout: Self.wait)
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
