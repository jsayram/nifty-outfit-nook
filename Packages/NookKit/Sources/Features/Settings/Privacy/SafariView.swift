import SafariServices
import SwiftUI

/// The app's pages on its website (https://niftyoutfitnook.pages.dev/), opened in the system's
/// in-app Safari view. The app itself makes no request: Safari loads the page, and the app can't
/// see what happens there.
///
/// The privacy policy and terms aren't written yet (Phase 19b writes them, 35b checks them before
/// submission), so until then these addresses show the site's own "not found" page.
nonisolated enum WebsiteLink: String, CaseIterable, Identifiable, Sendable {
    case privacyPolicy = "privacy"
    case terms

    static let site: URL = {
        guard let url = URL(string: "https://niftyoutfitnook.pages.dev/") else {
            preconditionFailure("The website's address is written wrong")
        }
        return url
    }()

    var id: String { rawValue }

    var url: URL {
        Self.site.appending(path: rawValue)
    }
}

/// `SFSafariViewController` for SwiftUI. Shown full screen, with Safari's own Done button.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
