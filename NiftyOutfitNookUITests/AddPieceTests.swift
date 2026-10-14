import XCTest

/// Add a piece and Edit (Phase 7b): adding by words end to end, editing from garment detail,
/// Cancel with unsaved changes, and a draft that survives the app being closed. The rules and
/// the word matcher are covered by the package tests; these check the real screens.
final class AddPieceTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// Describe in words, Save's checks, accepting the suggestions, then the piece in Closet.
    @MainActor
    func testAddByWordsAndSeeItInCloset() {
        let app = launchOnCloset("demo")
        tap("closet.addPiece", in: app)
        tap("addPiece.words", in: app)

        // Continue with nothing typed, then Save: the form says what's missing.
        tap("words.continue", in: app)
        tap("editor.toolbarSave", in: app)
        XCTAssertTrue(element("problem.name", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertEqual(element("problem.name", in: app).label, "Give it a name.")
        XCTAssertTrue(element("problem.category", in: app).exists)

        // Back to the words, describe it and accept every suggestion.
        tap("editor.back", in: app)
        type("Navy wool coat with big buttons", into: "field.description", in: app)
        tap("words.suggest", in: app)
        acceptEverySuggestion(in: app)
        tap("words.continue", in: app)
        let name = element("field.name", in: app)
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(name.value as? String, "Navy coat")
        // The problems went away with the accepted name and kind.
        XCTAssertFalse(element("problem.name", in: app).exists)

        tap("editor.toolbarSave", in: app)
        XCTAssertTrue(labelled("Navy coat is in your closet", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(gridPiece("Navy coat", in: app).waitForExistence(timeout: Self.wait))
    }

    /// Edit from garment detail: Cancel asks first when something changed, and Save changes
    /// shows on the detail.
    @MainActor
    func testEditAPieceAndSeeTheDetailChange() {
        let app = launchOnCloset("demo")
        openNavyTrousers(in: app)

        // Change the name, then Cancel: it asks, Keep editing stays, Discard changes leaves it.
        tap("garment.edit", in: app)
        replaceText(in: "field.name", with: "Navy work trousers", in: app)
        tap("editor.cancel", in: app)
        let keepEditing = app.buttons["Keep editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: Self.wait))
        keepEditing.tap()
        XCTAssertEqual(element("field.name", in: app).value as? String, "Navy work trousers")
        tap("editor.cancel", in: app)
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: Self.wait))
        discard.tap()
        XCTAssertTrue(element("garment.name", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertEqual(element("garment.name", in: app).label, "Navy dress pants")

        // Change it again and save: the detail shows the new name.
        tap("garment.edit", in: app)
        replaceText(in: "field.name", with: "Navy work trousers", in: app)
        tap("editor.toolbarSave", in: app)
        XCTAssertTrue(labelled("Changes saved", in: app).waitForExistence(timeout: Self.wait))
        let title = element("garment.name", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForLabel("Navy work trousers", of: title))
    }

    /// Abandon mid-add, close the app, open it again and resume.
    ///
    /// Stage A keeps drafts in memory, so the relaunch seeds the same draft with
    /// `-fixtures demo:draft=add` (the words typed here are the seeded draft's words). The
    /// package tests check that the form writes the draft as she goes.
    @MainActor
    func testAbandonMidAddThenResumeAfterRelaunch() {
        var app = launchOnCloset("demo")
        tap("closet.addPiece", in: app)
        tap("addPiece.words", in: app)
        type("Sage green cardigan with gold buttons, soft and cozy", into: "field.description", in: app)
        tap("words.suggest", in: app)
        acceptEverySuggestion(in: app)
        tap("words.continue", in: app)
        XCTAssertEqual(element("field.name", in: app).value as? String, "Sage cardigan")
        app.terminate()

        app = launchOnCloset("demo:draft=add")
        // Closet offers it.
        let message = element("closet.draft.message", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(message.label, "Sage cardigan isn’t in your closet yet.")
        // So does Add a piece, which is where she resumes it from here.
        tap("closet.addPiece", in: app)
        tap("draft.resume", in: app)
        let name = element("field.name", in: app)
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(name.value as? String, "Sage cardigan")
        XCTAssertTrue(app.buttons["editor.back"].exists)

        tap("editor.toolbarSave", in: app)
        XCTAssertTrue(labelled("Sage cardigan is in your closet", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertTrue(gridPiece("Sage cardigan", in: app).waitForExistence(timeout: Self.wait))
        // Saved, so nothing is waiting any more.
        XCTAssertTrue(message.waitForNonExistence(timeout: Self.wait))
    }

    // MARK: Helpers

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

    @MainActor
    private func openNavyTrousers(in app: XCUIApplication) {
        let search = app.searchFields["Search your closet"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait))
        search.tap()
        search.typeText("navy pants\n")
        let trousers = app.buttons["closet.garment.g-navy-trousers"]
        XCTAssertTrue(trousers.waitForExistence(timeout: Self.wait))
        trousers.tap()
        XCTAssertTrue(element("garment.name", in: app).waitForExistence(timeout: Self.wait))
    }

    /// A piece in the Closet grid, by its name.
    @MainActor
    private func gridPiece(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'closet.garment.' AND label == %@", name))
            .firstMatch
    }

    @MainActor
    private func acceptEverySuggestion(in app: XCUIApplication) {
        let accepts = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.accept'"))
        XCTAssertTrue(accepts.firstMatch.waitForExistence(timeout: Self.wait))
        for index in 0..<accepts.count {
            tap(accepts.element(boundBy: index).identifier, in: app)
        }
    }

    @MainActor
    private func type(_ text: String, into identifier: String, in app: XCUIApplication) {
        let field = element(identifier, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: Self.wait))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func replaceText(in identifier: String, with text: String, in app: XCUIApplication) {
        let field = element(identifier, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: Self.wait))
        // Tap near the end, so the cursor lands after the text before deleting it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        field.typeText(text)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func waitForLabel(_ label: String, of element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: Self.wait) == .completed
    }

    /// Taps a button by identifier, scrolling up to find it if it's below the screen.
    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "No button \(identifier)")
        var swipes = 0
        while !button.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        button.tap()
    }
}
