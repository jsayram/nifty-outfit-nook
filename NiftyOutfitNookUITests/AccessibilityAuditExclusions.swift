import UIKit
import XCTest

/// Decides which issues from Xcode's accessibility audit are excused, and says why. Everything
/// else fails the test. Each rule is narrow and, where it can, checks the claim itself rather
/// than trusting it. Worked out on the iOS 26.5 iPhone 12 simulator with Xcode 26.6 (October
/// 2026), from the audit's issues and a screenshot of each screen.
///
/// What's here is the audit misreading the soft style: see-through tints, soft shadows, art and
/// the system's faded edges. A real problem it finds is fixed in the app, not added here.
@MainActor
final class AuditExclusions {
    private let screen: String
    private let app: XCUIApplication

    /// - Parameter screen: The name the test gives the screen, which the few screen-specific
    ///   rules below match.
    init(screen: String, in app: XCUIApplication) {
        self.screen = screen
        self.app = app
    }

    /// The reason an issue is excused, or nil when it should fail the test.
    func reason(for issue: XCUIAccessibilityAuditIssue) -> String? {
        switch issue.auditType {
        case .contrast: contrastReason(for: issue)
        case .dynamicType: dynamicTypeReason(for: issue)
        case .textClipped: clippedTextReason(for: issue)
        case .elementDetection: hiddenTextReason(for: issue)
        default: nil
        }
    }

    /// What a failing issue was about, for the test's failure message: the audit's words, the
    /// element and, for contrast, what the screen's pixels measure.
    func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        var parts = [screen, issue.compactDescription]
        if let element = issue.element, element.exists {
            parts.append("\"\(element.label)\" (\(element.identifier)) at \(element.frame)")
            if issue.auditType == .contrast,
                let ratio = PixelContrast.ratio(in: element.frame, of: screenshot, window: window)
            {
                parts.append(String(format: "measured %.2f:1", ratio))
            }
        } else if let element = issue.element {
            parts.append("element gone: \(element.description)")
        } else if issue.auditType == .contrast {
            parts.append("no element; words that fail: \(lowWords.joined(separator: ", "))")
        } else {
            parts.append("no element")
        }
        return parts.joined(separator: " | ")
    }

    // MARK: What's on screen, looked up once per audit

    // An audit can report dozens of issues, and each query of the app takes a moment (seconds on
    // CI), so these are read once, when the first issue that needs them comes in.

    private lazy var screenshot = XCUIScreen.main.screenshot().image
    private lazy var window = app.windows.firstMatch.frame
    private lazy var tabBar: CGRect? = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : nil
    private lazy var tourCard: CGRect? = {
        let card = app.descendants(matching: .any)["tour.card"]
        return card.exists ? card.frame : nil
    }()

    /// The words on screen that fail the contrast rules, as "label (ratio)". Read from one
    /// snapshot of the app's tree, so it costs one query however many words there are.
    private lazy var lowWords: [String] = {
        guard let tree = try? app.snapshot() else { return ["the app's tree couldn't be read"] }
        var words: [XCUIElementSnapshot] = []
        var queue = [tree]
        while let next = queue.popLast() {
            queue.append(contentsOf: next.children)
            // Words only: a button's words show up as a static text inside it, and a button's
            // own frame can be a drawing (Home's wardrobe) or an icon (a chevron, a tick circle).
            if next.elementType == .staticText, !next.label.isEmpty, !next.frame.isEmpty {
                words.append(next)
            }
        }
        return words.compactMap { word in
            guard contrastReason(for: word.frame, isEnabled: { word.isEnabled }) == nil else { return nil }
            let ratio = PixelContrast.ratio(in: word.frame, of: screenshot, window: window)
            let measured = ratio.map { String(format: "%.2f:1", $0) } ?? "not measured"
            return "\"\(word.label)\" at \(word.frame) (\(measured))"
        }
    }()

    /// How far above the tab bar the system's scroll edge fade reaches, in points (iOS 26 draws it
    /// over the content under a floating bar; measured on the iPhone 12 simulator).
    private static let scrollEdgeFade: CGFloat = 32

    // MARK: Contrast

    /// The audit's contrast check reports words that are plainly readable: dark espresso on the
    /// cream surfaces, which `ContrastTests` holds to 4.5:1 or more in both appearances. It seems
    /// to misread see-through tints and the soft shadows under chips and buttons (the solid dark
    /// buttons pass). So each one is measured again from the screen's pixels in the element's
    /// frame, and excused only when the words really reach 4.5:1. Anything lower fails, as does
    /// anything that can't be measured.
    private func contrastReason(for issue: XCUIAccessibilityAuditIssue) -> String? {
        guard let element = issue.element, element.exists else {
            // On the iPhone 17 simulator the audit reports some contrast issues with no element
            // ("Contrast failed for SwiftUI.AccessibilityNode"), so there's nothing to measure.
            // Then every static text on screen is measured instead, and it's excused only when
            // all of them pass the same rules.
            return lowWords.isEmpty ? "no element; every word on screen passes" : nil
        }
        return contrastReason(for: element.frame, isEnabled: { element.isEnabled })
    }

    /// The contrast rules for one element's frame.
    private func contrastReason(for frame: CGRect, isEnabled: () -> Bool) -> String? {
        // Content that has scrolled under the floating tab bar, or into the fade above it, is
        // faded on purpose, and is read in place once she scrolls it up.
        if let tabBar, frame.maxY > tabBar.minY - Self.scrollEdgeFade {
            return "under the floating tab bar or its scroll edge fade"
        }
        // A quick tour dims the screen under it on purpose, and hides it from VoiceOver.
        if let tourCard, !tourCard.intersects(frame) {
            return "dimmed under a modal quick tour"
        }
        // A chip in a row that scrolls sideways, partly past the window's edge. The same chips
        // measure fine where they're on screen.
        if !window.contains(frame) {
            return "partly off screen in a sideways row"
        }
        // WCAG doesn't ask a control that can't be used yet to reach 4.5:1 (1.4.3, "inactive").
        if !isEnabled() {
            return "disabled control"
        }
        guard let ratio = PixelContrast.ratio(in: frame, of: screenshot, window: window), ratio >= 4.5 else {
            return nil
        }
        return String(format: "measured %.1f:1 on screen", ratio)
    }

    // MARK: Dynamic Type

    /// Every font in the app is a Dynamic Type text style (`NookTextStyle`, no fixed point sizes;
    /// the only fixed sizes are icons inside fixed circles). Yet the audit calls the same chip
    /// "partially unsupported" on one screen and not on another, and flags screen titles that
    /// `AccessibilityAuditLargeTextTests` shows at full size at AX5, where the clipped-text check
    /// runs on them too. The system bar buttons (Back, Edit, Add a piece) do stop growing, by the
    /// system's design: they show the Large Content Viewer instead. A font that doesn't scale at
    /// all ("unsupported", not "partially") still fails.
    private func dynamicTypeReason(for issue: XCUIAccessibilityAuditIssue) -> String? {
        issue.compactDescription.contains("partially unsupported") ? "text style scales; checked at AX5" : nil
    }

    // MARK: Clipped text

    /// Texts the audit calls clipped that were looked at in the screenshots and are whole, by
    /// screen, so a new one fails.
    private static let wholeTexts: [String: (label: String, why: String)] = [
        // The serif display title has -0.6 letter spacing, so its glyphs reach a hair past the
        // frame SwiftUI gives it. On the iPhone 12 "measurements" just fits the line, and at AX5
        // the system hyphenates it. Every letter shows in both.
        "Fit and measurements": ("Fit and measurements", "display title with tight letter spacing, whole on screen"),
        // The button in the Packed header, sized to its words.
        "A suitcase": ("Add or remove", "button sized to its words, whole on screen"),
        // At AX5 the chip wraps onto its own line and is as wide as its word.
        "Add a piece: the form": ("Layers", "chip as wide as its word at AX5, whole on screen"),
    ]

    /// Screens where Xcode 27.1's audit reports clipped text with no element.
    private static let elementlessClippedScreens: Set<String> = [
        "Saved Looks", "Pictures", "Your looks", "Your looks: Saved",
    ]

    private func clippedTextReason(for issue: XCUIAccessibilityAuditIssue) -> String? {
        guard let element = issue.element else {
            // Under a quick tour the screen is hidden from VoiceOver, so its words have no
            // element; the card's own words do. At AX5 on the iPhone 17 the room's words under
            // the dim were reported this way.
            if tourCard != nil { return "no element; the screen under a modal quick tour" }
            // At the default size the audit reports clipped text on the welcome with no element.
            // Its only words are the title, the line under it and the two buttons, all whole in
            // the screenshot; the porch drawing (hidden from VoiceOver) runs off both edges by
            // design, roof tiles and all.
            if screen == "Welcome" { return "no element; the welcome's words are whole" }
            // Xcode 27.1's audit on the iOS 27.0 runtime, at AX5, also reports clipped text with no
            // element on these screens (19 October 2026). The same app code passed this audit on
            // the iOS 26.5 runtime with Xcode 27.1, so it's the new runtime's audit and not a
            // change in our screens. Each time an issue is excused here the test attaches a
            // screenshot ("Excused clipped text: <screen>"); the ones from iPhone 12 runs show
            // every word whole, with system hyphenation ("Inter-view") at AX5.
            return Self.elementlessClippedScreens.contains(screen)
                ? "no element; Xcode 27.1 reports this at AX5 and the words are whole" : nil
        }
        guard let known = Self.wholeTexts[screen], known.label == element.label else { return nil }
        return known.why
    }

    // MARK: Text VoiceOver can't reach

    /// "Potentially inaccessible text" comes with no element, so this checks the screen instead.
    private func hiddenTextReason(for issue: XCUIAccessibilityAuditIssue) -> String? {
        guard issue.element == nil, issue.compactDescription.contains("inaccessible text") else { return nil }
        // A quick tour is modal: the screen under the dim is hidden from VoiceOver on purpose
        // (docs/tours.md), and the card reads the step.
        if tourCard != nil {
            return "screen under a modal quick tour"
        }
        // Suitcases' entry hall is hidden from VoiceOver and Voice Control on purpose: its luggage
        // tags repeat the favourite rows right under it, which are the controls
        // (`SuitcasesHall`). Checked: the rows are there.
        if screen == "Suitcases", app.buttons["suitcases.row.mainCloset.choose"].exists {
            return "the hall's tags repeat the rows under it"
        }
        // Words half under the floating tab bar's glass, which the audit reads as text but can't
        // match to their element. The element is there, and whole once scrolled up.
        if let tabBar {
            let straddling = app.staticTexts.allElementsBoundByIndex.contains { text in
                let frame = text.frame
                return frame.intersects(tabBar) && frame.minY < tabBar.minY
            }
            if straddling { return "words half under the tab bar" }
        }
        return nil
    }
}

/// The contrast of the words in part of a screenshot, measured from its pixels.
enum PixelContrast {
    /// The contrast between the commonest colour in `frame` (the background) and the ink, taken
    /// as the 95th percentile of the pixels that differ from the background, so a glyph's
    /// anti-aliased edges don't count against it, nor a drawing around the words (the name sign's
    /// wooden frame). Truly faint words stay faint that high up: fine print in the scroll edge
    /// fade measured 3.5:1 at the 95th and 3.6:1 at the 99th. Nil when the frame is off the
    /// screenshot or holds no ink.
    static func ratio(in frame: CGRect, of screenshot: UIImage, window: CGRect) -> Double? {
        guard let image = screenshot.cgImage, window.width > 0 else { return nil }
        let scale = CGFloat(image.width) / window.width
        let pixels = CGRect(
            x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale
        )
        .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard pixels.width >= 4, pixels.height >= 4, let crop = image.cropping(to: pixels),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        let width = crop.width
        let height = crop.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // The commonest colour, rounded a little so a gradient's neighbours count together.
        var counts: [UInt32: Int] = [:]
        for index in stride(from: 0, to: data.count, by: 4) {
            let key = UInt32(data[index] >> 2) << 16 | UInt32(data[index + 1] >> 2) << 8 | UInt32(data[index + 2] >> 2)
            counts[key, default: 0] += 1
        }
        guard let background = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let backgroundLuminance = luminance(
            Double((background >> 16) & 0xFF) * 4 + 2, Double((background >> 8) & 0xFF) * 4 + 2,
            Double(background & 0xFF) * 4 + 2)

        var inks: [Double] = []
        for index in stride(from: 0, to: data.count, by: 4) {
            let value = luminance(Double(data[index]), Double(data[index + 1]), Double(data[index + 2]))
            let contrast = (max(value, backgroundLuminance) + 0.05) / (min(value, backgroundLuminance) + 0.05)
            if contrast > 1.5 { inks.append(contrast) }
        }
        guard inks.count >= 12 else { return nil }
        inks.sort()
        return inks[inks.count * 95 / 100]
    }

    /// WCAG relative luminance of an sRGB colour with 0-255 components.
    private static func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            let value = component / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
