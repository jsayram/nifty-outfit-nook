import Foundation
import Models
@preconcurrency import UserNotifications

/// 27c: local notifications for jobs that finish while the app is in the background.
///
/// Nothing is asked at launch. Your looks explains first, the first time a job that can take a
/// while starts, and only her Notify me shows iOS's own alert. If she says no, the banner in the
/// app still works. The text is fixed per kind of job ("Your outfit ideas are ready") and never
/// names a piece, a look or anything she wrote; the identifier is the job's random ID. Her "Not
/// now" is kept in a `UserDefaults` suite and erased by Delete my data.
nonisolated public final class LocalJobNotifier: AIJobNotifier, ErasableStore, @unchecked Sendable {
    public static let suiteName = "com.jsayram.niftyoutfitnook.notifications"
    static let declinedKey = "jobs.offerDeclined"
    static let identifierPrefix = "aijob."

    // UserDefaults is thread-safe, which is why this class can be shared.
    private let defaults: UserDefaults

    public init(suiteName: String = LocalJobNotifier.suiteName) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func offer() async -> AIJobNotificationOffer {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return defaults.bool(forKey: Self.declinedKey) ? .off : .offer
        case .denied: return .off
        @unknown default: return .off
        }
    }

    public func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])) ?? false
    }

    public func declineOffer() async {
        defaults.set(true, forKey: Self.declinedKey)
    }

    public func notifyDone(_ kind: AIJob.Kind, id: AIJob.ID) async {
        guard await offer() == .allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = AIJobText.notificationTitle(kind)
        content.body = AIJobText.notificationBody
        content.threadIdentifier = "ai-jobs"
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: Self.identifier(id), content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    public func withdraw(_ id: AIJob.ID) async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(id)])
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(id)])
    }

    public func eraseAll() async throws(StoreError) {
        defaults.removeObject(forKey: Self.declinedKey)
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    static func identifier(_ id: AIJob.ID) -> String { identifierPrefix + id.rawValue }

    /// The job a tapped notification is about.
    public static func jobID(from identifier: String) -> AIJob.ID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return AIJob.ID(String(identifier.dropFirst(identifierPrefix.count)))
    }
}
