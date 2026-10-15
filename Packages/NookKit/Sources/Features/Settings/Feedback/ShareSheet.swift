import SwiftUI
import UIKit

/// The system share sheet with one piece of text, which tells us whether she sent it somewhere
/// or closed it. SwiftUI's `ShareLink` doesn't say, and Send feedback thanks her only when the
/// note really went.
///
/// The app reaches no network here: the app she picks (Messages, Mail, Notes) does the sending.
struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    /// The subject, for Mail.
    let subject: String
    /// Called once when the sheet closes: true when she sent or saved the text.
    let finished: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [ShareText(text: text, subject: subject)], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            finished(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The text with a subject line for apps that use one.
private final class ShareText: NSObject, UIActivityItemSource {
    let text: String
    let subject: String

    init(text: String, subject: String) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(
        _ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        text
    }

    func activityViewController(
        _ controller: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}
