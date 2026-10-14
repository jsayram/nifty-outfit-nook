import XCTest

/// Garment detail (Phase 7a): opening a piece from Closet, its actions, Remove from closet
/// (LR-16) and Recently deleted. The words and rules are covered by the package tests; these
/// check the real screens, sheets and navigation.
final class GarmentDetailTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// LR-16.2 and LR-16.3: Delete it moves the piece to Recently deleted, and Restore brings it
    /// back to Closet.
    @MainActor
    func testDeleteAPieceThenRestoreIt() {
        let app = launchOnCloset("demo")
        let trousers = openNavyTrousers(in: app)

        // The detail: name, Last worn, and its suitcases near the title (LR-10, LR-11).
        XCTAssertEqual(element("garment.name", in: app).label, "Navy dress pants")
        XCTAssertEqual(element("garment.lastWorn", in: app).label, "Last worn 5 days ago")
        XCTAssertTrue(app.buttons["garment.suitcase.s-weekend"].exists)

        // Remove from closet asks first, and Delete it lists the saved looks it affects.
        tap("garment.remove", in: app)
        tap("remove.delete", in: app)
        XCTAssertTrue(element("remove.affectedLooks", in: app).waitForExistence(timeout: Self.wait))
        tap("remove.delete.confirm", in: app)

        // Back on Closet without it, and Recently deleted now has two pieces.
        XCTAssertTrue(labelled("Navy dress pants is in Recently deleted", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForNonExistence(trousers))
        let recentlyDeleted = app.buttons["closet.recentlyDeleted"]
        XCTAssertTrue(recentlyDeleted.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(recentlyDeleted.label.contains("2"), recentlyDeleted.label)
        recentlyDeleted.tap()

        // Restore it from Recently deleted.
        let restore = app.buttons["recentlyDeleted.restore.g-navy-trousers"]
        XCTAssertTrue(restore.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["recentlyDeleted.restore.g-gray-leggings"].exists)
        restore.tap()
        XCTAssertTrue(labelled("Navy dress pants is back in your closet", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForNonExistence(restore))

        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(trousers.waitForExistence(timeout: Self.wait))
    }

    /// Mark as dirty while tracking is on (RD-11), Style with this and its choice, and
    /// "I don't have it any more" with Undo (LR-16.1).
    @MainActor
    func testLaundryStyleWithThisAndUndo() {
        let app = launchOnCloset("demo:laundry=some")
        let trousers = openNavyTrousers(in: app)

        // Mark as dirty, then the status says so.
        let status = element("garment.fact.status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(status.value as? String, "Clean")
        tap("garment.laundry", in: app)
        XCTAssertTrue(labelled("Marked as dirty", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertEqual(status.value as? String, "Dirty")

        // Style with this offers the two choices; Style me with it opens Style Me with the piece.
        tap("garment.styleWithThis", in: app)
        tap("styleWithThis.styleMe", in: app)
        XCTAssertTrue(element("stub.styleMe", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(element("styleMe.startingPiece", in: app).label.contains("Navy dress pants"))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        // I don't have it any more, then Undo from the toast.
        tap("garment.remove", in: app)
        tap("remove.noLongerOwned", in: app)
        tap("remove.noLongerOwned.confirm", in: app)
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: Self.wait))
        XCTAssertFalse(trousers.exists)
        undo.tap()
        XCTAssertTrue(trousers.waitForExistence(timeout: Self.wait))
    }

    // MARK: Helpers

    @MainActor
    private func launchOnCloset(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", fixtures]
        app.launch()
        let closet = app.tabBars.firstMatch.buttons["Closet"]
        XCTAssertTrue(closet.waitForExistence(timeout: Self.wait))
        closet.tap()
        return app
    }

    /// Searches for "navy pants" so the piece is near the top, then opens it.
    @MainActor
    private func openNavyTrousers(in app: XCUIApplication) -> XCUIElement {
        let search = app.searchFields["Search your closet"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait))
        search.tap()
        search.typeText("navy pants\n")
        let trousers = app.buttons["closet.garment.g-navy-trousers"]
        XCTAssertTrue(trousers.waitForExistence(timeout: Self.wait))
        trousers.tap()
        XCTAssertTrue(element("garment.name", in: app).waitForExistence(timeout: Self.wait))
        return trousers
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Any element with this label, such as a toast's message.
    @MainActor
    private func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Taps a button by identifier, scrolling up to find it if it's below the screen.
    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "No button \(identifier)")
        var swipes = 0
        while !button.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        button.tap()
    }

    @MainActor
    private func waitForNonExistence(_ element: XCUIElement) -> Bool {
        element.waitForNonExistence(timeout: Self.wait)
    }
}
