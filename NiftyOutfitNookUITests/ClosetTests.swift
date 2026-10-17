import XCTest

/// Closet browsing (Phase 6, RD-13, LR-09, LR-11): search, filter, open a piece, and the empty
/// closet. Search and filter combinations are covered by the package tests; these check the real
/// controls.
final class ClosetTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFilterSearchAndOpenAPiece() {
        let app = launchOnCloset("demo")
        let count = app.descendants(matching: .any)["closet.count"]
        XCTAssertTrue(count.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(count.label.hasSuffix("17 pieces"), count.label)

        // A piece chip filters, and says it's selected (LR-09).
        let shoes = app.buttons["closet.filter.kind.shoes"]
        XCTAssertTrue(shoes.waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(shoes.isSelected)
        shoes.tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.buttons["closet.garment.g-black-heels"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(app.buttons["closet.garment.g-cream-crop"].exists)
        XCTAssertTrue(count.label.hasSuffix("4 of 17 pieces"), count.label)

        // Clear brings everything back.
        app.buttons["closet.filter.clear"].tap()
        XCTAssertTrue(app.buttons["closet.garment.g-cream-crop"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(shoes.isSelected)

        // Search by name, then by suitcase name (LR-11.3).
        let search = searchField(in: app)
        XCTAssertTrue(search.waitUntilExists(timeout: Self.wait))
        search.tapUntilFocused(timeout: Self.wait)
        search.typeText("navy")
        let trousers = app.buttons["closet.garment.g-navy-trousers"]
        XCTAssertTrue(trousers.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.buttons["closet.garment.g-navy-cardigan"].exists)
        XCTAssertFalse(app.buttons["closet.garment.g-cream-crop"].exists)
        // VoiceOver hears its suitcases and when she last wore it (LR-10, LR-11.1).
        XCTAssertEqual(trousers.label, "Navy dress pants")
        XCTAssertTrue((trousers.value as? String)?.hasPrefix("In Jose's house and Weekend") == true)

        // Opening a piece goes to its detail (Phase 7a), and back.
        let name = app.descendants(matching: .any)["garment.name"]
        trousers.tapUntil(name, appears: Self.wait)
        XCTAssertEqual(name.label, "Navy dress pants")
        let back = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(back.tapUntil(timeout: Self.wait) { !name.exists }, "The piece didn't close")
        XCTAssertTrue(trousers.waitUntilExists(timeout: Self.wait))
    }

    /// RD-13.2: an empty closet explains how to add a piece, and Add a piece opens the form (7b).
    @MainActor
    func testEmptyClosetOffersToAddAPiece() {
        let app = launchOnCloset("empty")
        XCTAssertTrue(app.staticTexts["Your closet is empty"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(searchFieldExists(in: app))
        app.buttons["closet.empty.addPiece"].tapUntil(app.navigationBars["Add a piece"], appears: Self.wait)
        app.navigationBars["Add a piece"].buttons.firstMatch.tapUntil(
            app.buttons["closet.empty.describe"], appears: Self.wait)
    }

    @MainActor
    private func launchOnCloset(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", fixtures]
        app.launch()
        let closet = app.tabBars.firstMatch.buttons["Closet"]
        closet.tapUntilSelected(timeout: Self.wait)
        return app
    }

    /// The search field has the search field trait, so XCUITest sees a search field.
    @MainActor
    private func searchField(in app: XCUIApplication) -> XCUIElement {
        app.searchFields["Search your closet"]
    }

    @MainActor
    private func searchFieldExists(in app: XCUIApplication) -> Bool {
        searchField(in: app).exists
    }
}
