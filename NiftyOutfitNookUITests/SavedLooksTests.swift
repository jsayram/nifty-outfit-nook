import XCTest

/// Saved Looks (Phase 12a, RD-08, LR-09, LR-10): a look saved on Your looks found again by search
/// and opened, Delete look with Undo, and a frame on the Home shelf opening its look. Phase 12b:
/// Try it on makes a picture that opens its look and back, and a picture deleted from a look
/// comes back with Undo on the Pictures tab. Search, the filters, renaming, Wear today's records,
/// the swap rules and the picture links are covered by the package and snapshot tests; these
/// check the real screens, their navigation and buttons.
final class SavedLooksTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// Style me, Save look, then find it on Saved Looks by its name and open it.
    @MainActor
    func testASavedLookIsFoundBySearchAndOpens() {
        let app = launch()
        styleMeAndSave(in: app)

        // Its name, from the Saved tab's row ("Cream & navy: Cream knit sweater, …").
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "results.saved.r-")).firstMatch
        tap("results.tab.saved", in: app, showing: row)
        let lookID = String(row.identifier.dropFirst("results.saved.".count))
        let name = String(row.label.prefix { $0 != ":" })
        XCTAssertFalse(name.isEmpty)

        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        let search = app.searchFields["Search your looks"]
        search.tapUntilFocused(timeout: Self.wait)
        search.typeTextAndWait(name + "\n", timeout: Self.wait)
        let cell = app.buttons["savedLooks.look.\(lookID)"]
        XCTAssertTrue(cell.waitUntilExists(timeout: Self.wait), "Search didn't find \(name)")
        // The demo's saved looks with other names are filtered out.
        XCTAssertTrue(app.buttons["savedLooks.look.o-lace-date"].waitUntilGone(timeout: Self.wait))

        let title = element("lookDetail.name", in: app)
        cell.tapUntil(title, appears: Self.wait)
        XCTAssertEqual(title.label, name)
        XCTAssertTrue(element("lookDetail.facts", in: app).label.contains("Saved today"))
    }

    /// Delete look goes back to the grid without it, and Undo brings it back.
    @MainActor
    func testDeleteLookWithUndo() {
        let app = launch()
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        tap("savedLooks.look.o-lace-date", in: app, showing: element("lookDetail.name", in: app))
        // Delete look goes back to the grid.
        let delete = app.buttons["lookDetail.delete"]
        tap("lookDetail.delete", in: app) { !delete.exists }

        let lace = app.buttons["savedLooks.look.o-lace-date"]
        XCTAssertTrue(lace.waitUntilGone(timeout: Self.wait), "The look is still on Saved Looks")
        // The line over the looks keeps Undo after the toast has gone.
        let banner = element("savedLooks.deleted", in: app)
        XCTAssertTrue(banner.waitUntilExists(timeout: Self.wait))
        banner.buttons["Undo"].tapUntil(lace, appears: Self.wait)
        XCTAssertTrue(banner.waitUntilGone(timeout: Self.wait))
    }

    /// A frame under the Home shelf opens its look on Saved Looks; Back goes to the grid. The
    /// blazer she gave away shows Swap it, which opens Swap a piece on that piece.
    @MainActor
    func testAShelfFrameOpensItsLook() {
        let app = launch()
        let frame = app.buttons["home.frame.2"]
        XCTAssertTrue(frame.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(frame.label, "Saved look: Interview navy and pink")
        let title = element("lookDetail.name", in: app)
        frame.tapUntil(title, appears: Self.wait)
        XCTAssertEqual(title.label, "Interview navy and pink")
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Saved Looks"].isSelected)
        app.goBack(from: "Interview navy and pink", to: "Saved Looks", timeout: Self.wait)
        XCTAssertTrue(app.buttons["savedLooks.look.o-interview"].waitUntilExists(timeout: Self.wait))

        let swapIt = "lookPieces.swapIt.o-blazer-office-g-gray-blazer"
        tap("savedLooks.look.o-blazer-office", in: app, showing: app.buttons[swapIt])
        tap(swapIt, in: app, showing: app.navigationBars["Swap a piece"])
        XCTAssertTrue(app.buttons["swap.piece.layer"].isSelected)
    }

    /// Phase 12b: save a look on Your looks, Try it on, then See the picture opens it on Saved
    /// Looks; See the look opens the look, which lists the picture; Back returns to the picture,
    /// and Back again to the Pictures tab with the new picture first.
    @MainActor
    func testTryItOnMakesAPictureThatOpensItsLook() {
        let app = launch()
        styleMeAndSave(in: app)

        tap("results.tryOn", in: app, showing: element("tryOn.ready", in: app))
        XCTAssertTrue(element("tryOn.free", in: app).exists, "No note that simulated pictures are free")
        tap("tryOn.make", in: app, showing: element("tryOn.made", in: app))
        tap("tryOn.seePicture", in: app, showing: element("picture.title", in: app))

        // Saved Looks, on the new picture.
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Saved Looks"].isSelected)
        XCTAssertTrue(element("picture.facts", in: app).label.contains("Made today"))
        let seeLook = app.buttons["picture.seeLook"]
        XCTAssertTrue(seeLook.waitUntilExists(timeout: Self.wait))
        let name = String(seeLook.label.dropFirst("See the look: ".count))
        XCTAssertFalse(name.isEmpty, seeLook.label)

        // Its look, which lists the picture.
        tap("picture.seeLook", in: app, showing: app.navigationBars[name])
        let title = element("lookDetail.name", in: app)
        XCTAssertTrue(title.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(title.label, name)
        let pictureRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lookDetail.picture."))
        XCTAssertTrue(pictureRow.firstMatch.waitUntilExists(timeout: Self.wait), "The look doesn't list its picture")
        let pictureID = String(pictureRow.firstMatch.identifier.dropFirst("lookDetail.picture.".count))

        // Back to the picture, then back to the Pictures tab, newest first.
        app.goBack(from: name, to: "Try-on picture", timeout: Self.wait)
        XCTAssertTrue(app.buttons["picture.seeLook"].waitUntilExists(timeout: Self.wait))
        app.goBack(from: "Try-on picture", to: "Saved Looks", timeout: Self.wait)
        XCTAssertTrue(app.buttons["savedLooks.tab.pictures"].isSelected)
        XCTAssertTrue(app.buttons["savedLooks.picture.\(pictureID)"].waitUntilExists(timeout: Self.wait))
    }

    /// Phase 12b: a look's picture opens from the look, See the look goes back to it, and Delete
    /// picture comes back to the look without it. Undo on the Pictures tab brings it back.
    @MainActor
    func testDeleteAPictureFromItsLookWithUndo() {
        let app = launch()
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        tap("savedLooks.look.o-lace-date", in: app, showing: element("lookDetail.name", in: app))
        let pictureBar = app.navigationBars["Try-on picture"]
        tap("lookDetail.picture.p-lace", in: app, showing: pictureBar)
        XCTAssertTrue(element("picture.title", in: app).waitUntilExists(timeout: Self.wait))

        // See the look is Back here, not a second copy of the look.
        tap("picture.seeLook", in: app) { !pictureBar.exists }
        XCTAssertTrue(element("lookDetail.name", in: app).waitUntilExists(timeout: Self.wait))
        tap("lookDetail.picture.p-lace", in: app, showing: pictureBar)
        // Delete picture goes back to the look.
        tap("picture.delete", in: app) { !pictureBar.exists }
        XCTAssertTrue(element("lookDetail.name", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.buttons["lookDetail.picture.p-lace"].waitUntilGone(timeout: Self.wait))

        app.goBack(from: "Lace date night", to: "Saved Looks", timeout: Self.wait)
        app.buttons["savedLooks.tab.pictures"].tapUntilSelected(timeout: Self.wait)
        let banner = element("savedLooks.pictureDeleted", in: app)
        XCTAssertTrue(banner.waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(app.buttons["savedLooks.picture.p-lace"].exists)
        banner.buttons["Undo"].tapUntil(app.buttons["savedLooks.picture.p-lace"], appears: Self.wait)
    }

    /// Saved Looks' Profile button opens the real Profile, as Closet's does. It used to open a
    /// stand-in, because Saved Looks drew Closet's screens with its own switch, which had no
    /// Profile case.
    @MainActor
    func testProfileOpensFromSavedLooks() {
        let app = launch()
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        app.buttons["savedLooks.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        XCTAssertTrue(element("profile.deleteData", in: app).waitUntilExists(timeout: Self.wait), "Profile is missing")
        app.goBack(from: "Profile", to: "Saved Looks", timeout: Self.wait)
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        return app
    }

    /// From the Home laptop, Style me with the defaults and Save look on Simple.
    @MainActor
    private func styleMeAndSave(in app: XCUIApplication) {
        tap("home.laptop", in: app, showing: app.navigationBars["Style Me"])
        tap("styleMe.go", in: app, showing: app.buttons["results.version.simple"])
        // A second tap would unsave it, so it's tapped again only if the label didn't change.
        let save = app.buttons["results.save"]
        tap("results.save", in: app) { save.exists && save.label.contains("Saved") }
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

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
