import XCTest

/// Phase 33b's checkpoint on the simulator: setting up the try-on photo with the app's own camera.
/// A simulator has no camera and can't run Apple Vision, so `-fake-camera` opens the same camera
/// screen over a drawn stand-in (never a photo of anyone) that gives hints in turn, and the check
/// before saving reads the drawing with the stand-in analyzer. The rules behind it are package
/// tests (`FramingGuidanceTests`, `FramingCoachTests`, `TryOnPhotoCheckerTests`,
/// `TryOnCaptureModelTests`, `ProfileModelTests`); the real camera and live Vision are on the
/// device checklist (2.18, 2.19).
final class TryOnPhotoSetupTests: XCTestCase {
    static let wait = uiTestWait
    /// The stand-in camera gives a hint about every second and a half, and the check takes a moment.
    static let hintWait: TimeInterval = 45

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheCameraGuidesHerThenTheCheckAcceptsThePhotoAndSheUsesIt() throws {
        try skipOnPullRequests("A seeded closet and a scripted camera; the package tests cover each rule.")
        let app = launch(["-fake-camera"])
        openCamera(in: app)

        let hint = app.descendants(matching: .any)["tryOnCapture.hint"]
        XCTAssertTrue(hint.waitUntilLabel(contains: "Step back a little", timeout: Self.hintWait))
        keepScreenshot("33b-1-step-back")
        XCTAssertTrue(hint.waitUntilLabel(contains: "arms hang a little away", timeout: Self.hintWait))
        keepScreenshot("33b-2-arms-out")
        XCTAssertTrue(hint.waitUntilLabel(contains: "Hold still", timeout: Self.hintWait))
        keepScreenshot("33b-3-ready")

        // The timer takes the photo, and the phone checks it before it can be her try-on photo.
        // "Take another photo" is on the screen for a photo that works and for one that doesn't.
        let review = app.buttons["tryOnPhoto.another"]
        XCTAssertTrue(review.waitUntilExists(timeout: Self.hintWait), "No check result")
        XCTAssertTrue(app.staticTexts["This photo works"].exists)
        keepScreenshot("33b-4-photo-works")

        let use = app.buttons["tryOnPhoto.use"]
        XCTAssertTrue(use.waitUntilExists(timeout: Self.wait))
        app.scrollUntilHittable(use, up: 12, down: 12)
        use.tapUntil(timeout: Self.wait, else: "Use this photo did nothing") {
            !review.exists
        }
        XCTAssertTrue(app.descendants(matching: .any)["tryOnPhoto.own"].waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    func testAPhotoTheCheckRefusesCantBeKeptAndHerPhotoStays() throws {
        try skipOnPullRequests("The package tests cover the check; this shows the screen.")
        // The drawing has her facing away, so there's no face to hide.
        let app = launch(["-fake-camera", "away"])
        openCamera(in: app)

        // She taps the shutter herself.
        app.buttons["tryOnCapture.shutter"].tapUntil(timeout: Self.wait, else: "Shutter did nothing") {
            app.buttons["tryOnPhoto.another"].exists
        }
        XCTAssertTrue(app.staticTexts["This photo won’t work for try-on"].waitUntilExists(timeout: Self.hintWait))
        XCTAssertFalse(app.buttons["tryOnPhoto.use"].exists, "A refused photo must not be keepable")
        XCTAssertFalse(app.buttons["tryOnPhoto.keepAnyway"].exists)
        keepScreenshot("33b-5-photo-wont-work")

        // Keep my current photo goes back, and her photo is still there.
        app.buttons["tryOnPhoto.cancelCandidate"].tapUntil(
            timeout: Self.wait, else: "Keep my current photo did nothing"
        ) {
            app.buttons["tryOnPhoto.take"].exists
        }
        XCTAssertTrue(app.descendants(matching: .any)["tryOnPhoto.own"].exists)
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.toursOff + UITestLaunch.animationsOff + ["-seed-tryon", "-cloud-tryon"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: 120), "Home didn't open")
        return app
    }

    /// Profile, Your try-on photo, Take your photo.
    @MainActor
    private func openCamera(in app: XCUIApplication) {
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        let row = app.buttons["profile.tryOnPhoto"]
        XCTAssertTrue(row.waitUntilExists(timeout: Self.wait))
        app.scrollUntilHittable(row, up: 12, down: 12)
        let take = app.buttons["tryOnPhoto.take"]
        row.tapUntil(take, appears: Self.wait)
        app.scrollUntilHittable(take, up: 12, down: 12)
        take.tapUntil(app.buttons["tryOnCapture.shutter"], appears: Self.wait)
    }

    @MainActor
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
