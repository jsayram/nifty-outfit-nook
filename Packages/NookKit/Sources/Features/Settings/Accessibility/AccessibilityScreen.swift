import DesignSystem
import SwiftUI
import UIKit

/// Accessibility (Phase 14b), from Profile.
///
/// Neither the PRD nor the mockups ask for in-app accessibility options: PRD §16 asks the app to
/// follow the system (Dynamic Type to AX5, VoiceOver, Reduce Motion, contrast, 44-point targets).
/// So this screen adds no switches of its own. It shows what each iPhone setting is now and what
/// the app does with it, and opens Settings, where she changes them.
struct AccessibilityScreen: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        AccessibilityPage(openSettings: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        })
        .navigationTitle(SettingsText.accessibilityTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Profile.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
    }
}

/// Accessibility, top to bottom: each setting with its current state and what the app does with
/// it, then Open Settings. Separate from `AccessibilityScreen` so snapshot tests can draw it.
struct AccessibilityPage: View {
    var openSettings: () -> Void = {}
    /// Snapshot tests set these, since the system's values can't be set in the environment.
    var voiceOverOverride: Bool?
    var reduceMotionOverride: Bool?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsPage(
            header: SettingsHeader(title: SettingsText.accessibilityTitle, lede: SettingsText.accessibilityLede)
        ) {
            SettingsGroup(header: AccessibilityText.nowHeader, identifier: "accessibility.settings") {
                SettingsInfoRow(
                    title: AccessibilityText.textSize, detail: AccessibilityText.textSizeDetail,
                    value: AccessibilityText.textSizeValue(dynamicTypeSize), systemImage: "textformat.size")
                SettingsInfoRow(
                    title: AccessibilityText.voiceOver, detail: AccessibilityText.voiceOverDetail,
                    value: (voiceOverOverride ?? voiceOver) ? ProfileText.on : ProfileText.off,
                    systemImage: "speaker.wave.2")
                SettingsInfoRow(
                    title: AccessibilityText.reduceMotion, detail: AccessibilityText.reduceMotionDetail,
                    value: (reduceMotionOverride ?? reduceMotion) ? ProfileText.on : ProfileText.off,
                    systemImage: "wind")
                SettingsInfoRow(
                    title: AccessibilityText.darkAppearance, detail: AccessibilityText.darkAppearanceDetail,
                    value: colorScheme == .dark ? ProfileText.on : ProfileText.off, systemImage: "moon")
            }

            VStack(spacing: NookSpacing.small) {
                NookButton(
                    AccessibilityText.openSettings, systemImage: "gear", fillsWidth: true, action: openSettings
                )
                .accessibilityHint(Text(AccessibilityText.openSettingsHint))
                .accessibilityIdentifier("accessibility.openSettings")
                SettingsNote(AccessibilityText.whereToChange)
                    .floorCard()
            }
        }
    }
}

/// The words on Accessibility. Each line says only what the app has been checked to do.
nonisolated enum AccessibilityText {
    static var nowHeader: String {
        String(
            localized: "Your iPhone’s settings now", bundle: .module, comment: "Accessibility: section header")
    }

    static var textSize: String {
        String(localized: "Text size", bundle: .module, comment: "Accessibility: a setting")
    }

    static var textSizeDetail: String {
        String(
            localized: "Every screen’s words grow with it. At the largest sizes, Home turns into big rows.",
            bundle: .module, comment: "Accessibility: what the app does with Text size")
    }

    static func textSizeValue(_ size: DynamicTypeSize) -> String {
        if size.isAccessibilitySize {
            return String(localized: "Largest", bundle: .module, comment: "Accessibility: text size value")
        }
        if size == .large {
            return String(localized: "Default", bundle: .module, comment: "Accessibility: text size value")
        }
        return size > .large
            ? String(localized: "Larger", bundle: .module, comment: "Accessibility: text size value")
            : String(localized: "Smaller", bundle: .module, comment: "Accessibility: text size value")
    }

    static var voiceOver: String {
        String(localized: "VoiceOver", bundle: .module, comment: "Accessibility: a setting")
    }

    static var voiceOverDetail: String {
        String(
            localized: "Every button, and everything in your room, says what it is and where it goes.",
            bundle: .module, comment: "Accessibility: what the app does with VoiceOver")
    }

    static var reduceMotion: String {
        String(localized: "Reduce Motion", bundle: .module, comment: "Accessibility: a setting")
    }

    static var reduceMotionDetail: String {
        String(
            localized: "Things fade instead of sliding, and Maya’s z’s stay still.", bundle: .module,
            comment: "Accessibility: what the app does with Reduce Motion")
    }

    static var darkAppearance: String {
        String(localized: "Dark appearance", bundle: .module, comment: "Accessibility: a setting")
    }

    static var darkAppearanceDetail: String {
        String(
            localized: "Your room changes to evening, with the lamp on.", bundle: .module,
            comment: "Accessibility: what the app does in dark appearance")
    }

    static var openSettings: String {
        String(localized: "Open Settings", bundle: .module, comment: "Accessibility: the button")
    }

    static var openSettingsHint: String {
        String(
            localized: "Opens this app’s page in the Settings app.", bundle: .module,
            comment: "VoiceOver hint on Open Settings")
    }

    static var whereToChange: String {
        String(
            localized:
                "Text size, VoiceOver and Reduce Motion are in Settings, under Accessibility. Per-App Settings there can change them for this app only.",
            bundle: .module, comment: "Accessibility: under the button")
    }
}
