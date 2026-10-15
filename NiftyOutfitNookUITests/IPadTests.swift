import XCTest

/// Home and Closet on iPad (Phase 15a): the tab bar at the bottom, the tall and wide rooms, the
/// Closet sidebar with a piece beside the grid, turning the iPad without losing what's open, and
/// a narrow window falling back to the phone layouts.
///
/// Every test is skipped on an iPhone, so the class costs nothing in the phone runs. Run them on
/// an iPad simulator: `NOOK_SIM_ID=<iPad udid> scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadTests`
/// (see docs/ipad.md). The helpers are in `IPadTestCase`.
final class IPadTests: IPadTestCase {
    /// RD-01.6: the tab bar sits at the bottom in both orientations, the room is the tall one
    /// upright and the wide one sideways, and turning the iPad keeps a pushed screen.
    @MainActor
    func testHomeRoomInBothOrientations() throws {
        let app = try launch(orientation: .portrait)
        XCTAssertTrue(room("tall", in: app).waitForExistence(timeout: Self.wait), "No tall room upright")
        assertTabBarAtTheBottom(in: app)

        // Every pushed piece of furniture opens and comes back, upright.
        for (identifier, title) in [
            ("home.laptop", "Style Me"), ("home.helpDrawer", "Help"), ("home.privacyDrawer", "Privacy and terms"),
            ("home.nameSign", "Profile"),
        ] {
            app.buttons[identifier].tapWhenHittable(timeout: Self.wait)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: Self.wait), "\(identifier)")
            app.goBack(from: title, to: "Home", timeout: Self.wait)
        }

        // Turning it keeps Style Me open and sends nothing (RD-01.6).
        app.buttons["home.laptop"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(app.navigationBars["Your looks"].exists, "Turning the iPad started a request")
        app.goBack(from: "Style Me", to: "Home", timeout: Self.wait)

        XCTAssertTrue(room("wide", in: app).waitForExistence(timeout: Self.wait), "No wide room sideways")
        assertTabBarAtTheBottom(in: app)
        for (identifier, title) in [("home.feedbackDrawer", "Send feedback"), ("home.occasion", "Style Me")] {
            app.buttons[identifier].tapWhenHittable(timeout: Self.wait)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: Self.wait), "\(identifier)")
            if identifier == "home.occasion" {
                app.buttons["Close"].tapUntilGone(timeout: Self.wait)
            }
            app.goBack(from: title, to: "Home", timeout: Self.wait)
        }
        // The wardrobe and the suitcase switch to Closet.
        app.buttons["home.wardrobe"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Closet"].waitUntilSelected(timeout: Self.wait))
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        app.buttons["home.suitcase"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Suitcases"].waitForExistence(timeout: Self.wait))
    }

    /// Closet sideways: the sidebar, search, a filter, and a piece beside the grid with Edit.
    /// Turning the iPad upright keeps the piece beside the grid, without the sidebar.
    @MainActor
    func testClosetSidebarAndPieceBesideTheGrid() throws {
        let app = try launch(orientation: .landscapeLeft)
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(element("closet.sidebar", in: app).waitForExistence(timeout: Self.wait), "No sidebar")
        XCTAssertTrue(app.staticTexts["Pick a piece"].exists)

        // A chip in the sidebar filters the grid beside it.
        let shoes = app.buttons["closet.filter.kind.shoes"]
        shoes.tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(shoes.isSelected)
        XCTAssertTrue(app.buttons["closet.garment.g-black-heels"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(app.buttons["closet.garment.g-navy-trousers"].exists)
        app.buttons["closet.filter.clear"].tapWhenHittable(timeout: Self.wait)

        // Search, then a piece opens beside the grid, not over it.
        let search = app.searchFields["Search your closet"]
        search.tapWhenHittable(timeout: Self.wait)
        search.typeText("navy dress")
        let trousers = app.buttons["closet.garment.g-navy-trousers"]
        trousers.tapWhenHittable(timeout: Self.wait)
        let name = app.descendants(matching: .any)["garment.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(name.label, "Navy dress pants")
        XCTAssertTrue(trousers.isSelected, "The piece beside the grid should read as selected")
        XCTAssertTrue(element("closet.sidebar", in: app).exists, "The piece should open beside the grid")

        // Edit on the page opens the form over everything, and Back returns to the same piece.
        app.buttons["garment.edit"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Edit piece"].waitForExistence(timeout: Self.wait))
        app.navigationBars["Edit piece"].buttons.firstMatch.tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))

        // Upright: no sidebar, the piece still beside the grid.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(element("closet.sidebar", in: app).waitForNonExistence(timeout: Self.wait))
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(name.label, "Navy dress pants")
        XCTAssertTrue(app.buttons["closet.suitcases"].exists)
    }

    /// A window a third of the screen wide (Split View or Stage Manager) is compact: Home shows
    /// the phone room and Closet pushes a piece over the grid. Widening the window again moves
    /// the open piece beside the grid.
    @MainActor
    func testNarrowWindowFallsBackToThePhoneLayouts() throws {
        let app = try launch(orientation: .landscapeLeft)
        let full = app.windows.firstMatch.frame.width
        resize(app, toWidth: (full / 3).rounded())
        guard app.windows.firstMatch.frame.width < full * 0.5 else {
            throw XCTSkip("This simulator doesn't let the window be resized (Windowed Apps is off).")
        }
        XCTAssertTrue(room("upright", in: app).waitForExistence(timeout: Self.wait), "No phone room")
        assertTabBarAtTheBottom(in: app)

        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertFalse(element("closet.sidebar", in: app).exists)
        let search = app.searchFields["Search your closet"]
        search.tapWhenHittable(timeout: Self.wait)
        search.typeText("navy dress\n")
        app.buttons["closet.garment.g-navy-trousers"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Navy dress pants"].waitForExistence(timeout: Self.wait), "Not pushed")

        // Wide again: the same piece, now beside the grid.
        resize(app, toWidth: full)
        XCTAssertTrue(element("closet.sidebar", in: app).waitForExistence(timeout: Self.wait))
        let name = app.descendants(matching: .any)["garment.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(name.label, "Navy dress pants")
        XCTAssertFalse(app.navigationBars["Navy dress pants"].exists)
    }
}
