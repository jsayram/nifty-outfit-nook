import XCTest

/// Style Me, Your looks and Saved Looks on iPad (Phase 15b): the request beside its options, the
/// look beside its pieces and buttons, a saved look shown beside the Saved Looks grid, turning
/// the iPad with both open, going between a picture and its look, and a narrow window pushing a
/// look over the grid until it widens again.
///
/// Every test is skipped on an iPhone. Run them on an iPad simulator:
/// `NOOK_SIM_FAMILY=iPad scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadStyleMeAndSavedTests`
/// (see docs/ipad.md).
final class IPadStyleMeAndSavedTests: IPadTestCase {
    /// Style me from the laptop, save the look, then find it beside the Saved Looks grid. Turning
    /// the iPad keeps the result without styling again, and keeps the look beside the grid.
    @MainActor
    func testStyleMeSaveAndSeeTheLookBesideTheGrid() throws {
        let app = try launch(orientation: .landscapeLeft)
        XCTAssertTrue(room("wide", in: app).waitForExistence(timeout: Self.wait), "No wide room")
        app.buttons["home.laptop"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))

        // The request on the left, the options beside it.
        let source = element("styleMe.source", in: app)
        let comfort = element("styleMe.comfort", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: Self.wait))
        XCTAssertLessThan(source.frame.maxX, comfort.frame.minX, "The options aren't beside the request")

        app.buttons["styleMe.go"].tapWhenHittable(timeout: Self.wait)
        let save = app.buttons["results.save"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait))
        assertTheLookIsBesideTheButtons(in: app)
        let request = element("results.request", in: app).label

        // Turning the iPad keeps the result on screen and sends nothing (RD-01.6).
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait))
        XCTAssertFalse(element("results.styling", in: app).exists, "Turning the iPad started styling again")
        XCTAssertEqual(element("results.request", in: app).label, request)
        assertTheLookIsBesideTheButtons(in: app)

        // A tap that lands while the turned layout is still settling can be lost on CI, so tap
        // once more only if the button didn't change.
        save.tapWhenHittable(timeout: Self.wait)
        if !waitForLabel(of: save, containing: "Saved") {
            save.tapWhenHittable(timeout: Self.wait)
        }
        XCTAssertTrue(waitForLabel(of: save, containing: "Saved"), save.label)

        // The Saved tab fills the width; its tile names the look.
        app.buttons["results.tab.saved"].tapWhenHittable(timeout: Self.wait)
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "results.saved.r-")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "The saved look isn't on the Saved tab")
        let lookID = String(tile.identifier.dropFirst("results.saved.".count))
        let name = String(tile.label.prefix { $0 != ":" })

        // On Saved Looks, upright: the look opens beside the grid, not over it.
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.staticTexts["Pick a look"].waitForExistence(timeout: Self.wait))
        let search = app.searchFields["Search your looks"]
        search.tapWhenHittable(timeout: Self.wait)
        search.typeText(name + "\n")
        let cell = app.buttons["savedLooks.look.\(lookID)"]
        cell.tapWhenHittable(timeout: Self.wait)
        let title = element("lookDetail.name", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(title.label, name)
        XCTAssertTrue(cell.isSelected, "The look beside the grid should read as selected")
        XCTAssertTrue(element("savedLooks.detail", in: app).exists)
        XCTAssertFalse(app.navigationBars[name].exists, "The look was pushed over the grid")
        XCTAssertLessThan(cell.frame.maxX, title.frame.minX, "The look isn't beside the grid")

        // Sideways: the sidebar, with the same look still beside the grid.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element("savedLooks.sidebar", in: app).waitForExistence(timeout: Self.wait), "No sidebar")
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(title.label, name)
    }

    /// A picture beside the Pictures tab's grid opens its look beside the Looks tab's grid. A
    /// narrow window pushes the look over the grid, and widening it moves the look back beside.
    @MainActor
    func testPicturesAndANarrowWindow() throws {
        let app = try launch(orientation: .landscapeLeft)
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(element("savedLooks.sidebar", in: app).waitForExistence(timeout: Self.wait), "No sidebar")

        app.buttons["savedLooks.tab.pictures"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.staticTexts["Pick a picture"].waitForExistence(timeout: Self.wait))
        app.buttons["savedLooks.picture.p-lace"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(element("picture.title", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["savedLooks.picture.p-lace"].isSelected)

        // See the look: the Looks tab, with the look beside its grid.
        element("picture.seeLook", in: app).tapWhenHittable(timeout: Self.wait)
        let title = element("lookDetail.name", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(title.label, "Lace date night")
        XCTAssertTrue(app.buttons["savedLooks.tab.looks"].waitUntilSelected(timeout: Self.wait))
        XCTAssertTrue(app.buttons["savedLooks.look.o-lace-date"].isSelected)

        // A third of the screen: the phone page, with the same look pushed over it.
        let full = app.windows.firstMatch.frame.width
        resize(app, toWidth: (full / 3).rounded())
        guard app.windows.firstMatch.frame.width < full * 0.5 else {
            throw XCTSkip("This simulator doesn't let the window be resized (Windowed Apps is off).")
        }
        XCTAssertTrue(app.navigationBars["Lace date night"].waitForExistence(timeout: Self.wait), "Not pushed")
        XCTAssertFalse(element("savedLooks.sidebar", in: app).exists)
        app.goBack(from: "Lace date night", to: "Saved Looks", timeout: Self.wait)

        // Opened in the narrow window, then widened: beside the grid again.
        app.buttons["savedLooks.look.o-interview"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Interview navy and pink"].waitForExistence(timeout: Self.wait))
        resize(app, toWidth: full)
        XCTAssertTrue(element("savedLooks.sidebar", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(title.label, "Interview navy and pink")
        XCTAssertFalse(app.navigationBars["Interview navy and pink"].exists)
    }

    // MARK: - Helpers

    /// The look is on the left and Save look on the right, side by side.
    @MainActor
    private func assertTheLookIsBesideTheButtons(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let bundle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "lookBundle.")).firstMatch
        XCTAssertTrue(bundle.waitForExistence(timeout: Self.wait), "No look", file: file, line: line)
        let save = app.buttons["results.save"]
        XCTAssertLessThan(
            bundle.frame.maxX, save.frame.minX, "The look isn't beside its buttons", file: file, line: line)
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: Self.wait) == .completed
    }
}
