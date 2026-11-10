import XCTest

/// The lamp is the light switch (N3): a tap turns the whole app dark or light, VoiceOver hears
/// the change, and Profile's Dark mode switch shows the same choice and changes it back.
final class LightSwitchTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheLampAndTheDarkModeSwitchChangeTheAppearance() {
        let app = XCUIApplication()
        // `-onboarding skip` keeps the choice in memory, so the app starts on the simulator's
        // own appearance, which is light.
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))

        let lamp = app.buttons["home.lamp"]
        app.reveal(lamp, timeout: Self.wait)
        XCTAssertEqual(lamp.label, "Lamp")
        XCTAssertEqual(lamp.value as? String, "Lights on")
        let lit = brightness(of: app)

        // Lights off: the app goes dark.
        XCTAssertTrue(lamp.tapUntil(timeout: Self.wait) { (lamp.value as? String) == "Lights off" }, "Lamp")
        let dark = brightness(of: app)
        XCTAssertLessThan(dark, lit - 0.2, "The screen didn't get darker (\(lit) to \(dark))")

        // Profile's switch shows the same choice, and turning it off brings the lights back.
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        let darkMode = app.switches["profile.darkMode"]
        app.reveal(darkMode, timeout: Self.wait)
        XCTAssertEqual(darkMode.value as? String, "1")
        let before = darkMode.value as? String
        let flipped: @MainActor () -> Bool = { (darkMode.value as? String) != before }
        // The row is the switch; tap its knob, as `SettingsTests` does.
        let inner = darkMode.switches.firstMatch
        let didFlip =
            inner.exists
            ? inner.tapUntil(timeout: Self.wait, flipped)
            : darkMode.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tapUntil(
                timeout: Self.wait, flipped)
        XCTAssertTrue(didFlip, "Dark mode didn't flip")
        XCTAssertEqual(darkMode.value as? String, "0")
        app.goBack(from: "Profile", to: "Home", timeout: Self.wait)
        XCTAssertTrue(lamp.waitUntil(NSPredicate(format: "value == %@", "Lights on"), timeout: Self.wait))
        XCTAssertGreaterThan(brightness(of: app), dark + 0.2, "The screen didn't get lighter again")
    }

    /// The screen's mean brightness, 0 (black) to 1 (white), sampled on a coarse grid.
    @MainActor
    private func brightness(of app: XCUIApplication) -> Double {
        // Let the appearance change finish drawing.
        Thread.sleep(forTimeInterval: 0.5)
        guard let image = app.screenshot().image.cgImage else { return 0 }
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size)
        guard
            let context = CGContext(
                data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count * 255)
    }
}
