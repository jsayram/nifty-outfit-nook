import XCTest

/// Send feedback to the support queue (Phase 24d), on the fake sign-in and fake backend: signed
/// in, she writes a note, gives a reply address, attaches a screenshot, ticks the app details and
/// her closet's size, reads exactly what goes, and sends it. The checks that the fake server
/// received the note, that its screenshot carries no metadata and that what was shown matches
/// what was sent are made from outside the app, in the 24d checkpoint in the plan's progress log
/// (the fake writes `tmp/fake-backend-support.json` in the app's container); the package tests
/// (`FeedbackGatewayTests`, `ScreenshotPreparerTests`) and the backend's own tests cover them.
final class SupportFeedbackTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testANoteWithAScreenshotReachesTheSupportQueue() {
        let app = launch(signedIn: true)
        openFeedback(in: app)

        // Signed in, the queue's extras are there; the share sheet isn't how it goes.
        XCTAssertTrue(element("feedback.screenshot.add", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(element("feedback.supportPage", in: app).exists)

        let message = field("field.feedback.message", in: app)
        app.reveal(message, timeout: Self.wait)
        message.tapUntilFocused(timeout: Self.wait)
        message.typeTextAndWait("The hamper didn’t open Laundry.", timeout: Self.wait)

        let reply = field("field.feedback.reply", in: app)
        app.reveal(reply, timeout: Self.wait)
        reply.tapUntilFocused(timeout: Self.wait)
        reply.typeTextAndWait("lily@example.com", timeout: Self.wait)

        // The screenshot: a sample picture with a place, a camera and a caption planted in it.
        let sample = element("feedback.screenshot.sample", in: app)
        app.reveal(sample, timeout: Self.wait)
        sample.tapUntil(element("feedback.screenshot.thumbnail", in: app), appears: Self.wait)

        let details = app.switches["feedback.details"]
        app.reveal(details, timeout: Self.wait)
        flip(details)
        let closet = app.switches["feedback.closetCounts"]
        app.reveal(closet, timeout: Self.wait)
        flip(closet)

        // What the page lists is what will be sent.
        let preview = element("feedback.previewText", in: app)
        app.reveal(preview, timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: preview, containing: "Closet size:"), preview.label)
        for line in [
            "The hamper didn’t open Laundry.", "Reply address: lily@example.com", "Screenshot: 1 picture",
            "App version:", "iOS:", "Device:",
        ] {
            XCTAssertTrue(preview.label.contains(line), "The page doesn’t list “\(line)”: \(preview.label)")
        }
        XCTAssertFalse(preview.label.contains("Lily’s"), "Her name went into the note")
        keepScreenshot("24d-1-writing-with-screenshot")

        let send = element("feedback.send", in: app)
        app.reveal(send, timeout: Self.wait)
        send.tapUntil(element("feedback.sent", in: app), appears: Self.wait)
        let reference = element("feedback.reference", in: app)
        XCTAssertTrue(reference.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(reference.label.hasPrefix("Reference: NK-"), reference.label)
        keepScreenshot("24d-2-sent")
    }

    @MainActor
    func testSignedOutSendFeedbackStillUsesTheShareSheetAndHasTheSupportPage() {
        let app = launch(signedIn: false)
        openFeedback(in: app)
        // No reply address, screenshot or closet size: those belong to the queue.
        XCTAssertTrue(element("feedback.send", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(element("feedback.screenshot.add", in: app).exists)
        XCTAssertFalse(app.switches["feedback.closetCounts"].exists)
        XCTAssertFalse(app.textViews["field.feedback.reply"].exists || app.textFields["field.feedback.reply"].exists)
        // The support page is one tap away.
        XCTAssertTrue(element("feedback.supportPage", in: app).exists)
        keepScreenshot("24d-3-signed-out")
    }

    // MARK: Helpers

    @MainActor
    private func launch(signedIn: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.standard + ["-fixtures", "demo", "-feedback-sample-screenshot"]
            + (signedIn ? ["-fake-signed-in"] : [])
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: 120), "Home didn't open")
        return app
    }

    @MainActor
    private func openFeedback(in app: XCUIApplication) {
        let drawer = app.buttons["home.feedbackDrawer"]
        app.reveal(drawer, timeout: Self.wait)
        drawer.tapUntil(app.navigationBars["Send feedback"], appears: Self.wait)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func field(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let view = app.textViews[identifier]
        return view.exists ? view : app.textFields[identifier]
    }

    @MainActor
    private func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        let flipped: @MainActor () -> Bool = { toggle.exists && (toggle.value as? String) != before }
        let inner = toggle.switches.firstMatch
        let didFlip =
            inner.exists
            ? inner.tapUntil(timeout: Self.wait, flipped)
            : toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tapUntil(timeout: Self.wait, flipped)
        XCTAssertTrue(didFlip, "\(toggle) didn't flip")
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        element.waitUntil(NSPredicate(format: "label CONTAINS %@", text), timeout: Self.wait)
    }

    @MainActor
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
