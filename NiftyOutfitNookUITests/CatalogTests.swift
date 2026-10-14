import XCTest

/// The debug component catalog (`-catalog`). These check what VoiceOver and touch rely on:
/// labels, the selected trait, and that the sheet, search and toast work in the real app.
final class CatalogTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchCatalog() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-catalog"]
        app.launch()
        return app
    }

    @MainActor
    func testCatalogOpensWithTheLaunchArgument() {
        let app = launchCatalog()
        XCTAssertTrue(app.navigationBars["Component catalog"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The catalog replaces the app's tabs")
        XCTAssertTrue(app.buttons["Style me"].firstMatch.exists)
    }

    @MainActor
    func testChipsReportTheirSelection() {
        let app = launchCatalog()
        let tops = app.buttons["Tops"]
        let bottoms = app.buttons["Bottoms"]
        XCTAssertTrue(tops.waitForExistence(timeout: 10))
        XCTAssertTrue(tops.isSelected)
        XCTAssertFalse(bottoms.isSelected)

        bottoms.tap()
        XCTAssertTrue(bottoms.isSelected)
        XCTAssertTrue(tops.isSelected, "Piece filters combine")
    }

    @MainActor
    func testSegmentedSwitchMovesTheSelection() {
        let app = launchCatalog()
        let simple = app.buttons["Simple"]
        let dressedUp = app.buttons["Dressed up"]
        XCTAssertTrue(simple.waitForExistence(timeout: 10))
        XCTAssertTrue(simple.isSelected)

        dressedUp.tap()
        XCTAssertTrue(dressedUp.isSelected)
        XCTAssertFalse(simple.isSelected)
    }

    @MainActor
    func testClearSearchEmptiesTheField() {
        let app = launchCatalog()
        let clear = app.buttons["Clear search"]
        scrollTo(clear, in: app)
        clear.tap()
        XCTAssertFalse(app.buttons["Clear search"].exists)
    }

    @MainActor
    func testLoadingButtonSaysItIsLoading() {
        let app = launchCatalog()
        let loading = app.buttons["Styling"]
        XCTAssertTrue(loading.waitForExistence(timeout: 10))
        XCTAssertEqual(loading.value as? String, "Loading")
    }

    @MainActor
    func testSheetOpensAndCloses() {
        let app = launchCatalog()
        let open = app.buttons["Open the sheet"]
        scrollTo(open, in: app)
        open.tap()

        let closeButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Close"))
        XCTAssertTrue(closeButtons.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["I’ll be indoors"].firstMatch.exists)
        // The catalog also draws a copy of the sheet's header behind it; tap the one in the sheet.
        let sheetClose = closeButtons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(sheetClose, "The sheet has no Close button that can be tapped")
        sheetClose?.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.isHittable, "The sheet should be gone")
    }

    @MainActor
    func testToastAppearsWithItsAction() {
        let app = launchCatalog()
        let show = app.buttons["Show a toast"]
        scrollTo(show, in: app)
        show.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Saved to your looks"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo"].firstMatch.exists)
    }

    /// Swipes up until `element` is on screen and can be tapped.
    @MainActor
    private func scrollTo(
        _ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(app.navigationBars["Component catalog"].waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<15 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable, "Couldn't scroll to \(element)", file: file, line: line)
    }
}
