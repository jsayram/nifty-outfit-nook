import XCTest

/// Closet browsing (Phase 6, RD-13, LR-09, LR-11): search, filter, open a piece, and the empty
/// closet. Search and filter combinations are covered by the package tests; these check the real
/// controls.
final class ClosetTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFilterSearchAndOpenAPiece() {
        let app = launchOnCloset("demo")
        let count = app.descendants(matching: .any)["closet.count"]
        XCTAssertTrue(count.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(count.label.hasSuffix("17 pieces"), count.label)

        // A piece chip filters, and says it's selected (LR-09).
        let shoes = app.buttons["closet.filter.kind.shoes"]
        XCTAssertTrue(shoes.waitForExistence(timeout: Self.wait))
        XCTAssertFalse(shoes.isSelected)
        shoes.tap()
        XCTAssertTrue(shoes.isSelected)
        XCTAssertTrue(app.buttons["closet.garment.g-black-heels"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(app.buttons["closet.garment.g-cream-crop"].exists)
        XCTAssertTrue(count.label.hasSuffix("4 of 17 pieces"), count.label)

        // Clear brings everything back.
        app.buttons["closet.filter.clear"].tap()
        XCTAssertTrue(app.buttons["closet.garment.g-cream-crop"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(shoes.isSelected)

        // Search by name, then by suitcase name (LR-11.3).
        let search = searchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait))
        search.tap()
        search.typeText("navy")
        let trousers = app.buttons["closet.garment.g-navy-trousers"]
        XCTAssertTrue(trousers.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["closet.garment.g-navy-cardigan"].exists)
        XCTAssertFalse(app.buttons["closet.garment.g-cream-crop"].exists)
        // VoiceOver hears its suitcases and when she last wore it (LR-10, LR-11.1).
        XCTAssertEqual(trousers.label, "Navy dress pants")
        XCTAssertTrue((trousers.value as? String)?.hasPrefix("In Jose's house and Weekend") == true)

        // Opening a piece goes to its detail (a stand-in until Phase 7a), and back.
        trousers.tap()
        XCTAssertTrue(app.navigationBars["Navy dress pants"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.descendants(matching: .any)["stub.garment"].exists)
        app.navigationBars["Navy dress pants"].buttons.firstMatch.tap()
        XCTAssertTrue(trousers.waitForExistence(timeout: Self.wait))
    }

    /// RD-13.2: an empty closet explains how to add a piece, and Add a piece opens its stand-in.
    @MainActor
    func testEmptyClosetOffersToAddAPiece() {
        let app = launchOnCloset("empty")
        XCTAssertTrue(app.staticTexts["Your closet is empty"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(searchFieldExists(in: app))
        app.buttons["closet.empty.addPiece"].tap()
        XCTAssertTrue(app.navigationBars["Add a piece"].waitForExistence(timeout: Self.wait))
        app.navigationBars["Add a piece"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["closet.empty.describe"].waitForExistence(timeout: Self.wait))
    }

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
