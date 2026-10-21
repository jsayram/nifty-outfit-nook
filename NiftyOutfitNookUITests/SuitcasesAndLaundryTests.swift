import XCTest

/// Suitcases and Laundry (Phase 13): packing a suitcase and styling from it, and marking pieces
/// dirty and clean with the hamper on Home following along. The rules and words are covered by
/// the package tests; these check the real screens, sheets and navigation.
final class SuitcasesAndLaundryTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// LR-17, RD-09.2, FR-67: "+ Add a suitcase", pack three pieces, take one out and Undo, then
    /// Style me from this suitcase. Sending the request remembers it, so Home's suitcase shows it.
    @MainActor
    func testPackASuitcaseAndStyleFromIt() {
        let app = launch("demo")
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        tap("closet.suitcases", in: app, showing: app.navigationBars["Suitcases"])

        // "+ Add a suitcase" is in the bar, whatever is below (LR-17.1).
        let name = app.textFields["field.suitcaseEditor.name"]
        app.buttons["suitcases.add"].tapUntil(name, appears: Self.wait)
        name.tapUntilFocused(timeout: Self.wait)
        name.typeTextAndWait("Beach week", timeout: Self.wait)
        app.buttons["suitcaseEditor.icon.backpack"].tapUntilSelected(timeout: Self.wait)
        app.buttons["suitcaseEditor.save"].tapUntil(app.navigationBars["Beach week"], appears: Self.wait)

        // The new suitcase opens on the packing sheet.
        let count = element("packing.count", in: app)
        XCTAssertTrue(count.waitUntilExists(timeout: Self.wait), "The packing sheet didn't open")
        XCTAssertTrue(count.label.hasPrefix("Nothing packed yet"), count.label)
        for (search, id) in [("navy pants", "g-navy-trousers"), ("pink", "g-pink-blouse"), ("pumps", "g-nude-flats")] {
            let field = app.searchFields["Search your closet"]
            XCTAssertTrue(field.waitUntilExists(timeout: Self.wait))
            // Empties the last search before typing the next.
            let clear = app.buttons["Clear search"]
            if clear.exists { clear.tapUntilGone(timeout: Self.wait) }
            field.tapUntilFocused(timeout: Self.wait)
            field.typeTextAndWait("\(search)\n", timeout: Self.wait)
            // A second tap would unpack it, so it's tapped again only if it didn't say it's packed.
            let piece = app.buttons["packing.garment.\(id)"]
            piece.tapUntil(timeout: Self.wait, else: "\(id) wasn't packed") { piece.exists && piece.isSelected }
        }
        XCTAssertTrue(waitForLabel(of: count, containing: "3 packed"), count.label)
        app.buttons["Close"].tapUntilGone(timeout: Self.wait)

        // The three pieces are on the suitcase. One comes out, and Undo puts it back.
        let suitcaseCount = element("suitcase.count", in: app)
        XCTAssertTrue(waitForLabel(of: suitcaseCount, containing: "3 pieces"))
        app.buttons["suitcase.garment.g-pink-blouse.remove"].tapUntil(timeout: Self.wait, else: "It wasn't taken out") {
            self.label(of: suitcaseCount, contains: "2 pieces")
        }
        app.buttons["Undo"].tapUntil(timeout: Self.wait, else: "Undo didn't put it back") {
            self.label(of: suitcaseCount, contains: "3 pieces")
        }

        // Style me from this suitcase opens Style Me with it as the source, strict to it.
        let source = app.buttons["styleMe.source"]
        tap("suitcase.styleMe", in: app, showing: source)
        XCTAssertTrue(waitForLabel(of: source, containing: "Beach week"), source.label)
        tap("styleMe.go", in: app, showing: app.navigationBars["Your looks"])

        // Home's suitcase shows it now, as a favourite source (RD-01.3, RD-09.2).
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        let suitcase = app.buttons["home.suitcase"]
        XCTAssertTrue(
            waitForLabel(of: suitcase, containing: "Suitcase: Source, Beach week, 3 pieces, Suitcase only"),
            suitcase.label)

        // And it opens Suitcases on the Closet tab, where it's the chosen source.
        suitcase.tapUntil(app.navigationBars["Suitcases"], appears: Self.wait)
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Closet"].isSelected)
        let row = app.buttons.matching(identifier: "suitcases.row.mainCloset.choose").firstMatch
        XCTAssertTrue(row.waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(row.isSelected)
    }

    /// RD-11.3, RD-11.5, PRD §7.3: a piece marked dirty on its detail fills the hamper; Laundry
    /// cleans one with Undo, then the rest with Mark all clean, and the hamper empties.
    @MainActor
    func testMarkDirtyThenCleanInLaundry() {
        let app = launch("demo:laundry=some")
        let hamper = app.buttons["home.hamper"]
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, 2 to wash"), hamper.label)

        // Mark the navy trousers dirty on their detail.
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        let search = app.searchFields["Search your closet"]
        XCTAssertTrue(search.waitUntilExists(timeout: Self.wait))
        search.tapUntilFocused(timeout: Self.wait)
        search.typeTextAndWait("navy pants\n", timeout: Self.wait)
        let status = element("garment.fact.status", in: app)
        app.buttons["closet.garment.g-navy-trousers"].tapUntil(status, appears: Self.wait)
        // The button marks it clean again, so it's tapped again only if the status didn't change.
        // The status lasts; the "Marked as dirty" toast can be gone before a slow runner looks.
        tap("garment.laundry", in: app) { status.exists && status.value as? String == "Dirty" }

        // Home's hamper has three now, without a relaunch.
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, 3 to wash"), hamper.label)

        // The hamper opens Laundry on the Closet tab.
        hamper.tapUntil(app.navigationBars["Laundry"], appears: Self.wait)
        let count = element("laundry.count", in: app)
        XCTAssertTrue(waitForLabel(of: count, containing: "3 pieces in the wash"), count.label)

        // Mark clean on one piece, then Undo.
        tap("laundry.markClean.g-navy-trousers", in: app) { self.label(of: count, contains: "2 pieces in the wash") }
        app.buttons["Undo"].tapUntil(timeout: Self.wait, else: "Undo didn't put it back") {
            self.label(of: count, contains: "3 pieces in the wash")
        }

        // Two ticked, Clean selected asks first. A second tap would untick one, so each is
        // tapped again only if it didn't say it's ticked.
        let navy = app.buttons["laundry.select.g-navy-trousers"]
        tap("laundry.select.g-navy-trousers", in: app) { navy.exists && navy.isSelected }
        let firstOther = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'laundry.select.' AND identifier != 'laundry.select.g-navy-trousers'")
        ).firstMatch
        firstOther.tapUntil(timeout: Self.wait, else: "The second piece wasn't ticked") {
            firstOther.exists && firstOther.isSelected
        }
        let confirm = app.buttons["laundry.confirm"]
        tap("laundry.cleanSelected", in: app) { confirm.exists }
        confirm.tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: count, containing: "1 piece in the wash"), count.label)

        // Mark all clean asks too, then nothing is in the wash.
        tap("laundry.cleanAll", in: app) { confirm.exists }
        confirm.tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(element("laundry.empty", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(waitForLabel(of: count, containing: "Nothing in the wash"), count.label)

        // And Home's hamper is all clean.
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, All clean"), hamper.label)
    }

    /// At the largest text size each row in Laundry stacks, so the page stays inside the screen:
    /// every piece's name has room and its Mark clean can be reached. In one line the page was
    /// 435 points wide in a 402 point window, the names had no width at all, and Mark clean was
    /// cut off (QA, October 2026).
    ///
    /// Merges and nightly only, with the other AX5 checks. The AX5 audit sweep opens Laundry and
    /// reports clipped text and hit regions there, and the default-size walk covers Laundry on
    /// every pull request.
    @MainActor
    func testLaundryAtTheLargestTextSize() throws {
        try skipOnPullRequests("The AX5 audit sweep audits Laundry.")
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.standard + [
                "-fixtures", "demo:laundry=some",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        app.launch()
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        let tile = app.buttons["closet.laundry"]
        XCTAssertTrue(tile.waitUntilExists(timeout: Self.wait), "No Laundry tile")
        app.scrollUntilHittable(tile, up: 12)
        tile.tapUntil(app.navigationBars["Laundry"], appears: Self.wait)

        let window = app.windows.firstMatch.frame
        let count = element("laundry.count", in: app)
        XCTAssertTrue(count.waitUntilExists(timeout: Self.wait))
        XCTAssertGreaterThanOrEqual(count.frame.minX, window.minX + 8, "The header starts at the screen's edge")

        let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'laundry.markClean.'"))
        XCTAssertEqual(buttons.count, 2)
        for name in ["Black tee", "White lace top"] {
            let words = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (identifier BEGINSWITH 'laundry.')", name))
                .firstMatch
            XCTAssertTrue(words.waitUntilExists(timeout: Self.wait), "No row for \(name)")
            app.scrollUntilHittable(words, up: 12)
            XCTAssertGreaterThan(words.frame.width, 150, "\(name) has no room: \(words.frame)")
            XCTAssertLessThanOrEqual(words.frame.maxX, window.maxX)
        }
        for index in 0..<buttons.count {
            let button = buttons.element(boundBy: index)
            app.scrollUntilHittable(button, up: 12, down: 12)
            XCTAssertTrue(button.isHittable, "Can't reach \(button)")
            XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX, "Mark clean is cut off: \(button.frame)")
        }
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

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Taps a button by identifier, scrolling up to find it if it's below the screen, until
    /// `effect` holds (see `XCUIElement.tapUntil(timeout:_:)`).
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)", file: file, line: line)
        app.scrollUntilHittable(button, up: 12)
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

    /// Whether the element is there and its label contains `text`.
    @MainActor
    private func label(of element: XCUIElement, contains text: String) -> Bool {
        element.exists && element.label.contains(text)
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return element.waitUntil(predicate, timeout: Self.wait)
    }
}
