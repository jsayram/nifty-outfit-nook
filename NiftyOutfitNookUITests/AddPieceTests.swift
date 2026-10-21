import XCTest

/// Add a piece and Edit (Phase 7b): adding by words end to end, editing from garment detail,
/// Cancel with unsaved changes, and a draft that survives the app being closed. The rules and
/// the word matcher are covered by the package tests; these check the real screens.
final class AddPieceTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// Describe in words, Save's checks, accepting the suggestions, then the piece in Closet.
    @MainActor
    func testAddByWordsAndSeeItInCloset() {
        let app = launchOnCloset("demo")
        openDescribeInWords(in: app)

        // Continue with nothing typed, then Save: the form says what's missing.
        tap("words.continue", in: app, showing: app.buttons["editor.toolbarSave"])
        tap("editor.toolbarSave", in: app, showing: element("problem.name", in: app))
        XCTAssertEqual(element("problem.name", in: app).label, "Give it a name.")
        XCTAssertTrue(element("problem.category", in: app).exists)

        // Back to the words, describe it and accept every suggestion.
        tap("editor.back", in: app, showing: element("field.description", in: app))
        type("Navy wool coat with big buttons", into: "field.description", in: app)
        suggestAndAcceptEverySuggestion(in: app)
        tap("words.continue", in: app, showing: element("field.name", in: app))
        let name = element("field.name", in: app)
        XCTAssertTrue(name.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(name.value as? String, "Navy coat")
        // The problems went away with the accepted name and kind.
        XCTAssertFalse(element("problem.name", in: app).exists)

        // The toast isn't checked: on a slow CI runner it can come and go while XCUITest waits for
        // the app to settle. The piece in the grid is what matters.
        tap("editor.toolbarSave", in: app, showing: gridPiece("Navy coat", in: app))
    }

    /// Phase 21a: a piece added to her own closet is still there after the app closes. A fresh
    /// install (`-onboarding reset` also clears the store) through onboarding to the empty closet,
    /// a piece added by words, then a relaunch with no flags but the fixtures.
    @MainActor
    func testAPieceInHerOwnClosetIsKeptAfterARelaunch() {
        var app = XCUIApplication()
        app.launchArguments =
            ["-onboarding", "reset", "-tour", "off", "-fixtures", "demo"] + UITestLaunch.animationsOff
        app.launch()
        openHerOwnEmptyCloset(in: app)

        openDescribeInWords(in: app)
        type("Navy wool coat with big buttons", into: "field.description", in: app)
        suggestAndAcceptEverySuggestion(in: app)
        tap("words.continue", in: app, showing: element("field.name", in: app))
        tap("editor.toolbarSave", in: app, showing: gridPiece("Navy coat", in: app))
        app.terminate()

        // The relaunch: Home straight away, and the coat is in Closet.
        app = XCUIApplication()
        app.launchArguments = ["-tour", "off", "-fixtures", "demo"] + UITestLaunch.animationsOff
        app.launch()
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(gridPiece("Navy coat", in: app).waitUntilExists(timeout: Self.wait), "The piece wasn't kept")
    }

    /// Phase 22a: her own closet has real photos. Add a piece offers Take photo and Choose from
    /// Photos (no Paste) with the line about how photos are kept, and Take photo explains, in
    /// the app's words, before iOS asks; Not now asks nothing. The system camera and picker run
    /// outside the app and aren't driven here. On a simulator where camera access was already
    /// decided the explainer doesn't come, so the test only checks it when iOS hasn't asked yet.
    @MainActor
    func testHerOwnClosetOffersTheCameraAndPhotos() {
        let app = XCUIApplication()
        app.launchArguments =
            ["-onboarding", "reset", "-tour", "off", "-fixtures", "demo"] + UITestLaunch.animationsOff
        app.launch()
        openHerOwnEmptyCloset(in: app)

        tap("closet.addPiece", in: app, showing: app.buttons["addPiece.camera"])
        XCTAssertTrue(app.buttons["addPiece.library"].exists)
        XCTAssertFalse(app.buttons["addPiece.paste"].exists, "Paste isn't offered with real photos")
        XCTAssertTrue(element("addPiece.photoNote", in: app).exists)

        let notNow = app.buttons["camera.explainer.notNow"]
        tap("addPiece.camera", in: app) {
            notNow.exists || app.alerts.firstMatch.exists || !app.buttons["addPiece.camera"].isHittable
        }
        if notNow.exists {
            notNow.tapUntilGone(timeout: Self.wait)
            XCTAssertTrue(app.buttons["addPiece.camera"].waitUntilExists(timeout: Self.wait))
        }
    }

    /// Edit from garment detail: Cancel asks first when something changed, and Save changes
    /// shows on the detail.
    @MainActor
    func testEditAPieceAndSeeTheDetailChange() {
        let app = launchOnCloset("demo")
        openNavyTrousers(in: app)

        // Change the name, then Cancel: it asks, Keep editing stays, Discard changes leaves it.
        tap("garment.edit", in: app, showing: element("field.name", in: app))
        replaceText(in: "field.name", with: "Navy work trousers", in: app)
        let keepEditing = app.buttons["Keep editing"]
        tap("editor.cancel", in: app, showing: keepEditing)
        keepEditing.tapUntilGone(timeout: Self.wait)
        XCTAssertEqual(element("field.name", in: app).value as? String, "Navy work trousers")
        let discard = app.buttons["Discard changes"]
        tap("editor.cancel", in: app, showing: discard)
        discard.tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(element("garment.name", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(element("garment.name", in: app).label, "Navy dress pants")

        // Change it again and save: the detail shows the new name.
        tap("garment.edit", in: app, showing: element("field.name", in: app))
        replaceText(in: "field.name", with: "Navy work trousers", in: app)
        // Save closes the form.
        tap("editor.toolbarSave", in: app) { !app.buttons["editor.toolbarSave"].exists }
        let title = element("garment.name", in: app)
        XCTAssertTrue(title.waitUntilExists(timeout: Self.wait))
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
        openDescribeInWords(in: app)
        type("Sage green cardigan with gold buttons, soft and cozy", into: "field.description", in: app)
        suggestAndAcceptEverySuggestion(in: app)
        tap("words.continue", in: app, showing: element("field.name", in: app))
        XCTAssertEqual(element("field.name", in: app).value as? String, "Sage cardigan")
        app.terminate()

        app = launchOnCloset("demo:draft=add")
        // Closet offers it.
        let message = element("closet.draft.message", in: app)
        XCTAssertTrue(message.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(message.label, "Sage cardigan isn’t in your closet yet.")
        // So does Add a piece, which is where she resumes it from here.
        tap("closet.addPiece", in: app, showing: app.buttons["draft.resume"])
        tap("draft.resume", in: app, showing: element("field.name", in: app))
        let name = element("field.name", in: app)
        XCTAssertTrue(name.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(name.value as? String, "Sage cardigan")
        XCTAssertTrue(app.buttons["editor.back"].exists)

        tap("editor.toolbarSave", in: app, showing: gridPiece("Sage cardigan", in: app))
        // Saved, so nothing is waiting any more.
        XCTAssertTrue(message.waitUntilGone(timeout: Self.wait))
    }

    // MARK: Helpers

    @MainActor
    private func launchOnCloset(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", fixtures]
        app.launch()
        let closet = app.tabBars.firstMatch.buttons["Closet"]
        closet.tapUntilSelected(timeout: Self.wait)
        return app
    }

    @MainActor
    private func openNavyTrousers(in app: XCUIApplication) {
        let search = app.searchFields["Search your closet"]
        XCTAssertTrue(search.waitUntilExists(timeout: Self.wait))
        search.tapUntilFocused(timeout: Self.wait)
        search.typeTextAndWait("navy pants\n", timeout: Self.wait)
        let trousers = app.buttons["closet.garment.g-navy-trousers"]
        XCTAssertTrue(trousers.waitUntilExists(timeout: Self.wait))
        trousers.tapUntil(element("garment.name", in: app), appears: Self.wait)
    }

    /// A piece in the Closet grid, by its name.
    @MainActor
    private func gridPiece(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'closet.garment.' AND label == %@", name))
            .firstMatch
    }

    /// Closet's Add a piece, then Describe in words.
    @MainActor
    private func openDescribeInWords(in app: XCUIApplication) {
        tap("closet.addPiece", in: app, showing: app.buttons["addPiece.words"])
        tap("addPiece.words", in: app, showing: element("field.description", in: app))
    }

    /// Suggest details, then Accept on every suggestion. Accept says it's selected once taken.
    @MainActor
    private func suggestAndAcceptEverySuggestion(in app: XCUIApplication) {
        let accepts = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.accept'"))
        tap("words.suggest", in: app, showing: accepts.firstMatch)
        for index in 0..<accepts.count {
            let identifier = accepts.element(boundBy: index).identifier
            let accept = app.buttons[identifier]
            tap(identifier, in: app) { accept.exists && accept.isSelected }
        }
    }

    @MainActor
    private func type(_ text: String, into identifier: String, in app: XCUIApplication) {
        let field = element(identifier, in: app)
        XCTAssertTrue(field.waitUntilExists(timeout: Self.wait))
        field.tapUntilFocused(timeout: Self.wait)
        field.typeTextAndWait(text, timeout: Self.wait)
    }

    @MainActor
    private func replaceText(in identifier: String, with text: String, in app: XCUIApplication) {
        let field = element(identifier, in: app)
        XCTAssertTrue(field.waitUntilExists(timeout: Self.wait))
        // Tap near the end, so the cursor lands after the text before deleting it.
        let focused = field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tapUntil(timeout: Self.wait) {
            field.hasKeyboardNow
        }
        XCTAssertTrue(focused, "\(identifier) didn't get the keyboard")
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        field.typeTextAndWait(text, timeout: Self.wait)
    }

    /// From a fresh install through onboarding to her own, empty closet (kept in the store).
    @MainActor
    private func openHerOwnEmptyCloset(in app: XCUIApplication) {
        app.buttons["welcome.getStarted"].tapUntil(app.navigationBars["Your name"], appears: Self.wait)
        app.buttons["onboarding.skip"].tapUntil(app.navigationBars["Your closet stays here"], appears: Self.wait)
        app.buttons["onboarding.continue"].tapUntil(
            app.navigationBars["How you like clothes to fit"], appears: Self.wait)
        app.buttons["onboarding.skip"].tapUntil(app.navigationBars["Choose a starting closet"], appears: Self.wait)
        element("onboarding.closet.empty", in: app).tapUntilSelected(timeout: Self.wait)
        app.buttons["onboarding.continue"].tapUntil(app.navigationBars["Home"], appears: Self.wait)
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(element("closet.empty.addPiece", in: app).waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func waitForLabel(_ label: String, of element: XCUIElement) -> Bool {
        return element.waitUntil(NSPredicate(format: "label == %@", label), timeout: Self.wait)
    }

    /// Taps a button by identifier, scrolling up to find it if it's below the screen, until
    /// `effect` holds (see `XCUIElement.tapUntil(timeout:_:)`).
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)", file: file, line: line)
        app.scrollUntilHittable(button, up: 16)
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
}
