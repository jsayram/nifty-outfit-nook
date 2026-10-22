import XCTest

/// Phase 33c's checkpoint on the simulator: her first real try-on plays the privacy walkthrough
/// while the phone works, then the loading screen shows the real steps; "Watch how it works"
/// plays it again with Skip. Same set-up as `TryOnTests` (the drawn stand-in photo, the fake
/// backend's slow image service). The rules behind it are the package tests (`TryOnProgressTests`,
/// `PrivacyWalkthroughTests`, `RealTryOnModelTests`, `TryOnJobsTests`).
///
/// It needs a first run: her consent and "seen the walkthrough" are kept on the phone, so to run it
/// again locally uninstall the app first (`xcrun simctl uninstall <udid> com.jsayram.niftyoutfitnook`).
final class PrivacyWalkthroughTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheFirstPictureShowsTheWalkthroughThenTheRealSteps() throws {
        try skipOnPullRequests("A seeded closet and a 15-second job; the package tests cover each step.")
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.toursOff + UITestLaunch.animationsOff + [
                "-seed-tryon", "-cloud-tryon", "slow", "-subscription", "active",
            ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: 120), "Home didn't open")

        let frame = app.buttons.matching(NSPredicate(format: "label == %@", "Saved look: Sweater and trousers"))
            .firstMatch
        tap(frame, until: { app.buttons["lookDetail.tryOn"].exists })
        tap(app.buttons["lookDetail.tryOn"], until: { app.buttons["tryOn.make"].exists })
        tap(app.buttons["tryOn.make"], until: { app.buttons["tryOnConsent.allow"].exists })
        tap(
            app.buttons["tryOnConsent.allow"],
            until: { app.otherElements["walkthrough"].exists || app.staticTexts["walkthrough"].exists })

        // The first showing plays by itself, with no Skip, and says every step to VoiceOver.
        let walkthrough = app.descendants(matching: .any)["walkthrough"]
        XCTAssertTrue(walkthrough.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(walkthrough.label.hasPrefix("How your photo stays private."))
        XCTAssertTrue(walkthrough.label.contains("It never left your phone."))
        XCTAssertFalse(app.buttons["walkthrough.skip"].exists, "The first showing can't be skipped")
        keepScreenshot("33c-1-walkthrough")
        // The plan's line sits under it, word for word, with what our server does on the way.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Your face never leaves your phone."))
                .firstMatch.exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "up to 30 minutes")).firstMatch.exists)

        // It plays on from the start to the end: once the photo is out, it never starts over
        // (a regression when the sheet redrew behind it and reset the caption).
        let opening = "This is your photo. It starts on your iPhone."
        let sent = "Only this photo and your clothing photos are sent."
        var seenSent = false
        let deadline = Date().addingTimeInterval(20)
        while walkthrough.exists, Date() < deadline {
            if app.staticTexts[sent].exists { seenSent = true }
            if seenSent { XCTAssertFalse(app.staticTexts[opening].exists, "The walkthrough started over") }
        }

        // Under six seconds later the real steps take over, from the job's real state.
        let steps = app.descendants(matching: .any)["tryOn.steps"]
        XCTAssertTrue(steps.waitUntilExists(timeout: Self.wait), "The steps never showed")
        XCTAssertFalse(walkthrough.exists)
        let dressing = app.descendants(matching: .any)["tryOn.step.dressing"]
        XCTAssertTrue(dressing.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(dressing.label, "Dressing you, in progress")
        XCTAssertEqual(app.descendants(matching: .any)["tryOn.step.hidingFace"].label, "Hiding your face, done")
        XCTAssertEqual(
            app.descendants(matching: .any)["tryOn.step.restoring"].label,
            "Putting you back together on your phone, not started")
        keepScreenshot("33c-2-real-steps")

        // Watch how it works: a replay, with Skip.
        tap(app.buttons["tryOn.watchHow"], until: { app.buttons["walkthrough.skip"].exists })
        keepScreenshot("33c-3-replay-with-skip")
        tap(app.buttons["walkthrough.skip"], until: { !app.buttons["walkthrough.skip"].exists })
        XCTAssertTrue(steps.waitUntilExists(timeout: Self.wait))

        // Cancel stops the picture; nothing is kept.
        tap(app.buttons["tryOn.cancel"], until: { app.buttons["tryOn.make"].exists })
    }

    @MainActor
    private func tap(
        _ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(button)", file: file, line: line)
        XCUIApplication().scrollUntilHittable(button, up: 12, down: 12)
        button.tapUntil(timeout: Self.wait, else: "\(button) didn't do its job", file: file, line: line, effect)
    }

    @MainActor
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
