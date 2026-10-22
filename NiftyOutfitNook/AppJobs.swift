import Features
import Models
import Services
import UIKit
@preconcurrency import UserNotifications

/// Background AI jobs in the app (Phase 27c, `docs/background-ai-jobs.md`): one `AIJobs` for the
/// life of the process, a short background task when she leaves mid-job, and the notification
/// delegate that opens a job's result when she taps its notification.
///
/// What works when:
/// - In the app: a job keeps going on any screen; the banner and Home's dot say when it's done.
/// - In the background: iOS gives a short background task (about 30 seconds, iOS decides), so a
///   job that answers within it posts a local notification. After that the app is suspended and
///   the job is asked again, with its key, when she comes back.
/// - Closed: nothing runs on the phone. The job is asked again at the next launch, and the server
///   never charges it twice. A push when the app is closed needs APNs, which is designed in the
///   backend and waits on Jose's setup.
@MainActor
enum AppJobs {
    /// The app's jobs (her own closet's, and the debug sample closet's in memory), for the
    /// background task and the notification delegate. Set once at launch; only one is in use.
    static var all: [AIJobs] = []

    static let notifier = LocalJobNotifier()
    private static let delegate = NotificationDelegate()
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Jobs kept in the store, for her own closet.
    static func kept(in storage: NookStorage) -> AIJobs {
        AIJobs(store: storage.aiJobs, notifier: notifier)
    }

    /// Jobs in memory, for the debug sample closet, which comes back as it ships at each launch.
    static func inMemory() -> AIJobs {
        AIJobs(notifier: notifier)
    }

    static func installDelegate() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// The app is going to the background. With a job still running, asks iOS for a little time,
    /// so a job that answers soon still lands and posts its notification. The job's state is saved
    /// first, so a job iOS stops is picked up again at the next foreground or launch.
    static func didEnterBackground() {
        guard let jobs = all.first(where: { !$0.activeJobs.isEmpty }), backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ai-jobs") {
            Task { @MainActor in endBackgroundTask() }
        }
        Task { @MainActor in
            await jobs.idle()
            await jobs.saved()
            endBackgroundTask()
        }
    }

    private static func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// In the app, the banner says a job is done, so the system's banner isn't shown. A tapped
    /// notification opens the job's result.
    ///
    /// The completion-handler forms, on the main actor: with the `async` forms, iOS 26 ran the
    /// completion off the main thread after a tap, and UIKit stopped the app (found in the 27c
    /// checkpoint).
    private final class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([])
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            if let id = LocalJobNotifier.jobID(from: response.notification.request.identifier) {
                for jobs in AppJobs.all where jobs.job(id) != nil { jobs.requestOpen(id) }
            }
            completionHandler()
        }
    }
}
