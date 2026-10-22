import DesignSystem
import Models
import SwiftUI

/// What the app says about a finished job (Phase 27c). Never a piece's name, a look or anything
/// she wrote: the same words go into a notification, which shows on the Lock Screen.
nonisolated enum AIJobText {
    static func title(_ kind: AIJob.Kind, done: Bool) -> String {
        switch (kind, done) {
        case (.styling, true):
            String(localized: "Your looks are ready", bundle: .module, comment: "Banner and notification: styling done")
        case (.styling, false):
            String(
                localized: "Your outfit ideas didn’t finish", bundle: .module,
                comment: "Banner: a styling job didn't finish")
        case (.askStylist, true):
            String(localized: "The stylist answered", bundle: .module, comment: "Banner and notification: answer ready")
        case (.askStylist, false):
            String(
                localized: "The stylist couldn’t answer this time", bundle: .module,
                comment: "Banner: an Ask stylist job didn't finish")
        case (.tryOn, true):
            String(
                localized: "Your try-on picture is ready", bundle: .module,
                comment: "Banner and notification: try-on done")
        case (.tryOn, false):
            String(
                localized: "Your try-on picture didn’t finish", bundle: .module,
                comment: "Banner: a try-on job didn't finish")
        }
    }

    static func detail(done: Bool) -> String {
        done
            ? String(localized: "Tap to see them.", bundle: .module, comment: "Banner: what tapping it does")
            : String(localized: "Tap to try again.", bundle: .module, comment: "Banner: what tapping a failed job does")
    }

    /// The notification's body: the same for every kind, and it names nothing of hers.
    static var notificationBody: String {
        String(
            localized: "Open Outfit Nook to see them.", bundle: .module, comment: "Notification body for a finished job"
        )
    }

    /// The notification's title, which is the banner's.
    static func notificationTitle(_ kind: AIJob.Kind) -> String {
        switch kind {
        case .styling:
            String(
                localized: "Your outfit ideas are ready", bundle: .module, comment: "Notification title: styling done")
        case .askStylist, .tryOn: title(kind, done: true)
        }
    }
}

/// 27c: the calm banner at the top of the app when a job finishes while she's elsewhere in it.
/// Tapping it opens the result; the close button just hides it (the tab's dot stays until she
/// sees the result). VoiceOver reads it out when it appears; it grows with Dynamic Type and
/// doesn't go away on a timer.
struct AIJobBanner: View {
    let jobs: AIJobs
    let open: (AIJob) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let id = jobs.announcement, let job = jobs.job(id) {
                content(job)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        AccessibilityNotification.Announcement(AIJobText.title(job.kind, done: job.state == .done))
                            .post()
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: jobs.announcement)
    }

    private func content(_ job: AIJob) -> some View {
        let done = job.state == .done
        return HStack(alignment: .center, spacing: NookSpacing.small) {
            Button {
                open(job)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
                    Image(systemName: done ? "sparkles" : "exclamationmark.circle")
                        .foregroundStyle(.nook.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AIJobText.title(job.kind, done: done))
                            .nookTextStyle(.headline)
                            .foregroundStyle(.nook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(AIJobText.detail(done: done))
                            .nookTextStyle(.note)
                            .foregroundStyle(.nook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("jobs.banner")
            Button {
                jobs.dismissAnnouncement()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.nook.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Hide", bundle: .module, comment: "VoiceOver: hides the job banner"))
            .accessibilityIdentifier("jobs.banner.hide")
        }
        .padding(NookSpacing.small)
        // Solid, so the screen under it (a navigation bar's buttons) never shows through.
        .background {
            NookRadius.shape(NookRadius.group)
                .fill(Color.nook.surface)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .padding(.horizontal, NookSpacing.medium)
        .padding(.top, NookSpacing.xSmall)
    }
}
