import XCTest

/// The Style Me request (Phase 10a, RD-02): opening it from the laptop, the calendar and a
/// garment's Style with this, setting each option in its sheet, the states that stop it, and
/// Style me leading to Your looks with the request. The words and rules are covered by the
/// package tests; these check the real screen, sheets and navigation.
final class StyleMeTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// RD-02.2: each row opens its sheet and shows the new value; closing a sheet keeps the
    /// others. Style me opens the results with exactly what was chosen.
    @MainActor
    func testSetEachOptionThenStyleMe() {
        let app = launch("demo")
        open("home.laptop", in: app)

        // The defaults (RD-02.3).
        let occasion = app.buttons["styleMe.occasion"]
        XCTAssertTrue(occasion.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(occasion.label, "Occasion: Office")
        XCTAssertTrue(app.buttons["styleMe.go"].isEnabled)

        choose("styleMe.occasion", then: "occasion.brunch", in: app)
        XCTAssertTrue(waitForLabel(of: occasion, containing: "Brunch"), occasion.label)

        // LR-18: Comfort says how today's comfort differs from her usual fit.
        let comfort = app.buttons["styleMe.comfort"]
        choose("styleMe.comfort", then: "comfort.fitted", in: app)
        XCTAssertTrue(waitForLabel(of: comfort, containing: "Today: fitted (you usually like relaxed)"), comfort.label)

        // The Colour sheet stays open while she picks a colour, a strength and a place.
        tap("styleMe.color", in: app, showing: app.buttons["color.navy"])
        for chip in ["color.navy", "color.strength.required", "color.scope.shoes"] {
            tap(chip, in: app) { app.buttons[chip].exists && app.buttons[chip].isSelected }
        }
        XCTAssertTrue(app.buttons["color.navy"].isSelected)
        app.buttons["Close"].tapUntilGone(timeout: Self.wait)
        let color = app.buttons["styleMe.color"]
        XCTAssertTrue(waitForLabel(of: color, containing: "Navy · shoes · required"), color.label)

        // LR-03: Preferences, with exactly the two values.
        tap("styleMe.preferences", in: app, showing: app.buttons["preferences.mineAndOneIdea"])
        XCTAssertTrue(app.buttons["preferences.mineAndOneIdea"].isSelected)
        let preferences = app.buttons["styleMe.preferences"]
        tap("preferences.onlyMine", in: app) { preferences.exists && preferences.label.contains("Only mine") }

        // The weather row keeps 5a's sheet.
        choose("styleMe.weather", then: "weather.indoors", in: app)

        // Source: a suitcase. The other choices are kept.
        choose("styleMe.source", then: "source.s-weekend", in: app)
        let source = app.buttons["styleMe.source"]
        XCTAssertTrue(waitForLabel(of: source, containing: "Weekend"), source.label)
        XCTAssertTrue(occasion.label.contains("Brunch"))

        // Style me: Your looks repeats the request (LR-05a), and Only mine from a suitcase means
        // Something new has no piece she doesn't own (LR-05b.2).
        tap("styleMe.go", in: app, showing: app.navigationBars["Your looks"])
        let line = element("results.request", in: app)
        XCTAssertTrue(line.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(line.label, "Brunch · Weekend · Indoors")
        let somethingNew = app.buttons["results.version.somethingNew"]
        tap("results.version.somethingNew", in: app) { somethingNew.exists && somethingNew.isSelected }
        let description = element("results.versionDescription", in: app)
        XCTAssertTrue(waitForLabel(of: description, containing: "another way with your own pieces"), description.label)

        // Back on Style Me, every choice is still there.
        app.goBack(from: "Your looks", to: "Style Me", timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: color, containing: "Navy · shoes · required"), color.label)
    }

    /// The calendar opens Style Me on the Occasion sheet, and Other takes a few words.
    @MainActor
    func testCalendarAsksForTheOccasion() {
        let app = launch("demo")
        open("home.occasion", in: app)
        let other = app.buttons["occasion.other"]
        XCTAssertTrue(other.waitUntilExists(timeout: Self.wait), "The Occasion sheet didn't open")
        XCTAssertTrue(app.buttons["occasion.office"].isSelected)
        let note = app.textFields["occasion.otherNote"]
        other.tapUntil(note, appears: Self.wait)
        note.tapUntilFocused(timeout: Self.wait)
        note.typeTextAndWait("Museum visit", timeout: Self.wait)
        let occasion = app.buttons["styleMe.occasion"]
        tap("occasion.done", in: app) { occasion.exists && occasion.label.contains("Other: Museum visit") }
    }

    /// An empty suitcase stops Style me and offers another source (PRD §8.1, FR-67).
    @MainActor
    func testAnEmptySuitcaseStopsStyleMe() {
        let app = launch("demo")
        open("home.laptop", in: app)
        choose("styleMe.source", then: "source.s-spring", in: app)
        let notice = element("styleMe.notice.suitcaseEmpty", in: app)
        XCTAssertTrue(notice.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(notice.label.contains("Spring trip is empty"), notice.label)
        XCTAssertFalse(app.buttons["styleMe.go"].isEnabled)

        tap("styleMe.notice.suitcaseEmpty.chooseSource", in: app, showing: app.buttons["source.mainCloset"])
        tap("source.mainCloset", in: app) { !notice.exists }
        XCTAssertTrue(app.buttons["styleMe.go"].isEnabled)
    }

    /// A fresh install: Style Me can't style, and Add a piece is right there.
    @MainActor
    func testAnEmptyClosetOffersAddAPiece() {
        let app = launch("empty")
        open("home.laptop", in: app)
        tap("styleMe.notice.closetEmpty.addPiece", in: app, showing: app.navigationBars["Add a piece"])
    }

    /// "Style me with it" on a garment opens Style Me with that piece, and it goes in the request.
    @MainActor
    func testStyleWithThisSetsTheStartingPiece() {
        let app = launch("demo")
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        let search = app.searchFields["Search your closet"]
        XCTAssertTrue(search.waitUntilExists(timeout: Self.wait))
        search.tapUntilFocused(timeout: Self.wait)
        search.typeTextAndWait("navy pants\n", timeout: Self.wait)
        tap("closet.garment.g-navy-trousers", in: app, showing: app.buttons["garment.styleWithThis"])
        tap("garment.styleWithThis", in: app, showing: app.buttons["styleWithThis.styleMe"])
        let start = app.buttons["styleMe.startingPiece"]
        tap("styleWithThis.styleMe", in: app, showing: start)

        XCTAssertTrue(waitForLabel(of: start, containing: "Navy dress pants"), start.label)
        // Every version is built around it.
        tap("styleMe.go", in: app, showing: app.navigationBars["Your looks"])
        let piece = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Navy dress pants")).firstMatch
        XCTAssertTrue(piece.waitUntilExists(timeout: Self.wait), "The starting piece isn't in the look")
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", fixtures]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        return app
    }

    /// Taps a Home control and waits for Style Me.
    @MainActor
    private func open(_ identifier: String, in app: XCUIApplication) {
        tap(identifier, in: app, showing: app.navigationBars["Style Me"])
    }

    /// Opens a row's sheet, picks a choice that closes it, and waits for it to close.
    @MainActor
    private func choose(_ row: String, then choice: String, in app: XCUIApplication) {
        let button = app.buttons[choice]
        tap(row, in: app, showing: button)
        tap(choice, in: app) { !button.exists }
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

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        return element.waitUntil(NSPredicate(format: "label CONTAINS %@", text), timeout: Self.wait)
    }
}
