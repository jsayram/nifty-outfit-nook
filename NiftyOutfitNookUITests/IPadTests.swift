import XCTest

/// Home and Closet on iPad (Phase 15a): the tab bar at the bottom, the tall and wide rooms, the
/// Closet sidebar with a piece beside the grid, turning the iPad without losing what's open, and
/// a narrow window falling back to the phone layouts.
///
/// Every test is skipped on an iPhone, so the class costs nothing in the phone runs. Run them on
/// an iPad simulator: `NOOK_SIM_ID=<iPad udid> scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadTests`
/// (see docs/ipad.md).
final class IPadTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

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

    // MARK: - Helpers

    @MainActor
    private func launch(orientation: UIDeviceOrientation) throws -> XCUIApplication {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad layouts are checked on an iPad simulator.")
        }
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", "demo"]
        app.launch()
        // A window size left by an earlier run survives a relaunch, so start full screen.
        // SpringBoard's frame is the screen in portrait.
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard").frame.size
        let long = max(screen.width, screen.height)
        let short = min(screen.width, screen.height)
        resize(app, toWidth: orientation.isLandscape ? long : short)
        return app
    }

    /// Drags the window's bottom-right corner. iPadOS 26 resizes a window about its centre, so
    /// the corner moves half the change in width. Stops when the width is within 8 points.
    @MainActor
    private func resize(_ app: XCUIApplication, toWidth target: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<4 {
            let frame = app.windows.firstMatch.frame
            guard abs(frame.width - target) >= 8 else { return }
            let corner = origin.withOffset(CGVector(dx: frame.maxX - 5, dy: frame.maxY - 5))
            let goal = origin.withOffset(CGVector(dx: frame.maxX - 5 + (target - frame.width) / 2, dy: frame.maxY - 5))
            corner.press(forDuration: 0.4, thenDragTo: goal)
            _ = app.windows.firstMatch.waitForExistence(timeout: 2)
        }
    }

    @MainActor
    private func assertTabBarAtTheBottom(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "No tab bar", file: file, line: line)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(bar.frame.minY, window.midY, "The tab bar isn't at the bottom", file: file, line: line)
    }

    @MainActor
    private func room(_ kind: String, in app: XCUIApplication) -> XCUIElement {
        element("home.room.\(kind)", in: app)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
}

extension XCUIElement {
    /// Waits until a tab or other selectable button says it's selected.
    @MainActor
    fileprivate func waitUntilSelected(timeout: TimeInterval) -> Bool {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: self)
        return XCTWaiter().wait(for: [selected], timeout: timeout) == .completed
    }
}
