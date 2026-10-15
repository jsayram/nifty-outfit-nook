import Foundation
import Models
import UIKit

/// The words shared by the desk-drawer and settings screens (Phase 14b).
nonisolated enum SettingsText {
    static var helpTitle: String {
        String(localized: "Help", bundle: .module, comment: "Screen title")
    }

    static var helpLede: String {
        String(
            localized: "Short answers that work offline. Opening help never changes what you’re doing.",
            bundle: .module, comment: "Help, under the title")
    }

    static var feedbackTitle: String {
        String(localized: "Send feedback", bundle: .module, comment: "Screen title")
    }

    static var feedbackLede: String {
        String(
            localized: "A private note to the developer. It isn’t posted anywhere.", bundle: .module,
            comment: "Send feedback, under the title")
    }

    static var privacyTitle: String {
        String(localized: "Privacy and terms", bundle: .module, comment: "Screen title")
    }

    static var privacyLede: String {
        String(
            localized: "What stays here, what would be sent, and when.", bundle: .module,
            comment: "Privacy and terms, under the title")
    }

    static var accessibilityTitle: String {
        String(localized: "Accessibility", bundle: .module, comment: "Profile row and screen title")
    }

    static var accessibilityLede: String {
        String(
            localized: "The app follows your iPhone’s settings.", bundle: .module,
            comment: "Accessibility, under the title")
    }

    static var deleteTitle: String {
        String(localized: "Delete my data", bundle: .module, comment: "Profile row and screen title")
    }

    static var deleteLede: String {
        String(
            localized: "Everything you’ve added, from this iPhone.", bundle: .module,
            comment: "Delete my data, under the title")
    }

    /// "Nifty Outfit Nook · 0.1 (14) · test build with sample data", at the end of Help.
    static func versionLine(_ app: AppVersion) -> String {
        String(
            localized: "Nifty Outfit Nook · \(app.version) (\(app.build)) · test build with sample data",
            bundle: .module, comment: "Help: the app's version at the bottom, with its build number")
    }
}

/// The app's version and build number, from its Info.plist.
nonisolated struct AppVersion: Hashable, Sendable {
    var version: String
    var build: String

    static var current: AppVersion {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppVersion(
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?")
    }
}

extension FeedbackDiagnostics {
    /// The details Send feedback can add, read from this app and this device: the version,
    /// the build, the iOS version and the model identifier (such as "iPhone13,2"). Nothing else.
    @MainActor static var current: FeedbackDiagnostics {
        let app = AppVersion.current
        return FeedbackDiagnostics(
            appVersion: app.version, build: app.build, systemVersion: UIDevice.current.systemVersion,
            deviceModel: modelIdentifier)
    }

    /// The hardware model, such as "iPhone13,2". The simulator reports the model it simulates.
    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
