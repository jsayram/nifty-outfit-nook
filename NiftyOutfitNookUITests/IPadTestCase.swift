import XCTest

/// What the iPad UI tests share (Phases 15a and 15b): launching in an orientation, full screen,
/// resizing the window by its corner, and finding elements. Every test skips itself on an
/// iPhone, so the classes cost nothing in the phone runs (docs/ipad.md).
class IPadTestCase: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// - Parameter tour: the `-tour` flag. Tours are off unless a test is about them (Phase 16a).
    @MainActor
    func launch(orientation: UIDeviceOrientation, tour: String = "off") throws -> XCUIApplication {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad layouts are checked on an iPad simulator.")
        }
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.skipOnboarding + ["-tour", tour, "-fixtures", "demo"]
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
    func resize(_ app: XCUIApplication, toWidth target: CGFloat) {
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
    func assertTabBarAtTheBottom(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "No tab bar", file: file, line: line)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(bar.frame.minY, window.midY, "The tab bar isn't at the bottom", file: file, line: line)
    }

    @MainActor
    func room(_ kind: String, in app: XCUIApplication) -> XCUIElement {
        element("home.room.\(kind)", in: app)
    }

    @MainActor
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
}
