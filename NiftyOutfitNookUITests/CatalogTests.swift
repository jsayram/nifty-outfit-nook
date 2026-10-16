import XCTest

/// The debug component catalog (`-catalog`). These check what VoiceOver and touch rely on:
/// labels, the selected trait, and that the sheet, search and toast work in the real app.
///
/// Tests that need a page further down open the catalog on that page alone (`-catalog-page`),
/// since swiping through the whole catalog took minutes on CI.
final class CatalogTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Opens the catalog, or only its page `page` (a catalog page ID such as `search`).
    @MainActor
    private func launchCatalog(page: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-catalog"] + (page.map { ["-catalog-page", $0] } ?? [])
        app.launch()
        return app
    }

    @MainActor
    func testCatalogOpensWithTheLaunchArgument() {
        let app = launchCatalog()
        XCTAssertTrue(app.navigationBars["Component catalog"].waitUntilExists(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The catalog replaces the app's tabs")
        XCTAssertTrue(app.buttons["Style me"].firstMatch.exists)
    }

    @MainActor
    func testChipsReportTheirSelection() {
        let app = launchCatalog()
        let tops = app.buttons["Tops"]
        let bottoms = app.buttons["Bottoms"]
        XCTAssertTrue(tops.waitUntilExists(timeout: 10))
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
        XCTAssertTrue(simple.waitUntilExists(timeout: 10))
        XCTAssertTrue(simple.isSelected)

        dressedUp.tap()
        XCTAssertTrue(dressedUp.isSelected)
        XCTAssertFalse(simple.isSelected)
    }

    @MainActor
    func testClearSearchEmptiesTheField() {
        let app = launchCatalog(page: "search")
        let clear = app.buttons["Clear search"]
        scrollTo(clear, in: app)
        clear.tap()
        XCTAssertFalse(app.buttons["Clear search"].exists)
    }

    @MainActor
    func testLoadingButtonSaysItIsLoading() {
        let app = launchCatalog()
        let loading = app.buttons["Styling"]
        XCTAssertTrue(loading.waitUntilExists(timeout: 10))
        XCTAssertEqual(loading.value as? String, "Loading")
    }

    @MainActor
    func testSheetOpensAndCloses() {
        let app = launchCatalog(page: "sheet")
        let open = app.buttons["Open the sheet"]
        scrollTo(open, in: app)
        open.tap()

        let closeButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Close"))
        XCTAssertTrue(closeButtons.firstMatch.waitUntilExists(timeout: 5))
        XCTAssertTrue(app.buttons["I’ll be indoors"].firstMatch.exists)
        // The catalog also draws a copy of the sheet's header behind it; tap the one in the sheet.
        let sheetClose = closeButtons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(sheetClose, "The sheet has no Close button that can be tapped")
        sheetClose?.tap()
        XCTAssertTrue(open.waitUntilExists(timeout: 5))
        XCTAssertTrue(open.isHittable, "The sheet should be gone")
    }

    @MainActor
    func testToastAppearsWithItsAction() {
        let app = launchCatalog(page: "toast")
        let show = app.buttons["Show a toast"]
        scrollTo(show, in: app)
        show.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Saved to your looks"].firstMatch.waitUntilExists(timeout: 5))
        XCTAssertTrue(app.buttons["Undo"].firstMatch.exists)
    }

    /// The look bundle page (Phase 9), at the end of the catalog: a bundle is one VoiceOver
    /// element naming its pieces, a thumbnail is one button, and Find one names its piece.
    @MainActor
    func testLookBundlesReadAsOneElement() {
        let app = launchCatalog(page: "lookBundles")
        let thumbnail = app.buttons["Simple: Cream blouse, Navy trousers, Tan loafers"]
        scrollTo(thumbnail, in: app)

        // One element that names every piece. (The catalog page's identifier replaces the
        // bundle's own inside the catalog, so match the words.)
        let somethingNew = app.otherElements.matching(
            NSPredicate(
                format: "label == %@",
                "Office, something new: Camel blazer (not in your closet), Cream blouse, Navy trousers, Tan loafers"))
        XCTAssertEqual(somethingNew.count, 1)

        thumbnail.tap()
        XCTAssertTrue(app.staticTexts["Tapped: Simple"].waitUntilExists(timeout: 5))

        let findOne = app.buttons["Find one like Camel blazer"]
        scrollTo(findOne, in: app, swipes: 10, up: false)
        findOne.tap()
        XCTAssertTrue(app.staticTexts["Tapped: Find one: Camel blazer"].waitUntilExists(timeout: 5))
    }

    /// Scrolls until `element` is on screen and can be tapped (see `XCUIApplication.dragPage`).
    @MainActor
    private func scrollTo(
        _ element: XCUIElement, in app: XCUIApplication, swipes: Int = 15, up: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(app.navigationBars["Component catalog"].waitUntilExists(timeout: 10), file: file, line: line)
        for _ in 0..<swipes {
            if element.exists && element.isHittable { break }
            app.dragPage(up: up)
        }
        XCTAssertTrue(element.isHittable, "Couldn't scroll to \(element)", file: file, line: line)
    }
}
