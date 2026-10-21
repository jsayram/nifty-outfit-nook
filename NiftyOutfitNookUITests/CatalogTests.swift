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
    private func launchCatalog(page: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-catalog"] + (page.map { ["-catalog-page", $0] } ?? []) + extra
        app.launch()
        return app
    }

    /// The catalog opens in place of the app's tabs, and its components say what VoiceOver needs:
    /// the loading button says it is loading, chips and the segmented switch say which is
    /// selected. One launch for what were four tests (October 2026); the checks are the same.
    @MainActor
    func testCatalogOpensAndItsComponentsReportTheirState() {
        let app = launchCatalog()
        XCTAssertTrue(app.navigationBars["Component catalog"].waitUntilExists(timeout: uiTestWait))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The catalog replaces the app's tabs")
        XCTAssertTrue(app.buttons["Style me"].firstMatch.exists)

        let loading = app.buttons["Styling"]
        XCTAssertTrue(loading.waitUntilExists(timeout: uiTestWait))
        XCTAssertEqual(loading.value as? String, "Loading")

        let tops = app.buttons["Tops"]
        let bottoms = app.buttons["Bottoms"]
        XCTAssertTrue(tops.waitUntilExists(timeout: uiTestWait))
        XCTAssertTrue(tops.isSelected)
        XCTAssertFalse(bottoms.isSelected)
        // The catalog's chips never say they're hittable, but take a tap.
        bottoms.tapUntil(timeout: uiTestWait, else: "\(bottoms) didn't become selected") {
            bottoms.exists && bottoms.isSelected
        }
        XCTAssertTrue(tops.isSelected, "Piece filters combine")

        let simple = app.buttons["Simple"]
        let dressedUp = app.buttons["Dressed up"]
        XCTAssertTrue(simple.waitUntilExists(timeout: uiTestWait))
        XCTAssertTrue(simple.isSelected)
        dressedUp.tapUntil(timeout: uiTestWait, else: "\(dressedUp) didn't become selected") {
            dressedUp.exists && dressedUp.isSelected
        }
        XCTAssertFalse(simple.isSelected)
    }

    @MainActor
    func testClearSearchEmptiesTheField() {
        let app = launchCatalog(page: "search")
        let clear = app.buttons["Clear search"]
        scrollTo(clear, in: app)
        clear.tapUntilGone(timeout: uiTestWait)
    }

    @MainActor
    func testSheetOpensAndCloses() {
        let app = launchCatalog(page: "sheet")
        let open = app.buttons["Open the sheet"]
        scrollTo(open, in: app)
        // The catalog also draws a copy of the sheet's header on the page, Close and all, so the
        // sheet adds a second Close.
        let closeButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Close"))
        let onThePage = closeButtons.count
        open.tapUntil(timeout: uiTestWait, else: "The sheet didn't open") { closeButtons.count > onThePage }
        XCTAssertTrue(app.buttons["I’ll be indoors"].firstMatch.exists)
        // Tap the one in the sheet.
        let sheetClose = closeButtons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(sheetClose, "The sheet has no Close button that can be tapped")
        sheetClose?.tapUntil(timeout: uiTestWait, else: "The sheet didn't close") {
            closeButtons.count == onThePage
        }
        XCTAssertTrue(open.waitUntilExists(timeout: uiTestWait))
        XCTAssertTrue(open.isHittable, "The sheet should be gone")
    }

    @MainActor
    func testToastAppearsWithItsAction() {
        // The toast stays longer, so a slow runner still finds it.
        let app = launchCatalog(page: "toast", extra: ["-toasts-stay"])
        let show = app.buttons["Show a toast"]
        scrollTo(show, in: app)
        // On CI the runner once took seconds to deliver the tap and no toast came, so tap once
        // more if it doesn't show.
        let toast = app.descendants(matching: .any)["Saved to your looks"].firstMatch
        show.tapUntil(toast, appears: uiTestWait)
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

        thumbnail.tapUntil(app.staticTexts["Tapped: Simple"], appears: uiTestWait)

        let findOne = app.buttons["Find one like Camel blazer"]
        scrollTo(findOne, in: app, swipes: 10, up: false)
        findOne.tapUntil(app.staticTexts["Tapped: Find one: Camel blazer"], appears: uiTestWait)
    }

    /// Scrolls until `element` is on screen and can be tapped (see `XCUIApplication.dragPage`).
    @MainActor
    private func scrollTo(
        _ element: XCUIElement, in app: XCUIApplication, swipes: Int = 15, up: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            app.navigationBars["Component catalog"].waitUntilExists(timeout: uiTestWait), file: file, line: line)
        for _ in 0..<swipes {
            if element.exists && element.isHittable { break }
            app.dragPage(up: up)
        }
        XCTAssertTrue(element.isHittable, "Couldn't scroll to \(element)", file: file, line: line)
    }
}
