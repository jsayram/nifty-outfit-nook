import ClerkAuth
import Features
import Foundation
import Models
import Networking

/// The app's one gateway to the backend (Phase 24a). With a Clerk publishable key and the backend
/// URL set (Configs/Secrets.xcconfig, docs/backend-switch.md) it signs in through Clerk and calls
/// the Convex deployment; without them it runs on the fake sign-in and the in-process fake
/// backend. Screens see only `AccountService` either way.
@MainActor
enum AppGateway {
    static let settings = GatewaySettings(info: Bundle.main.infoDictionary ?? [:])
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    #if DEBUG
        /// The debug gateway screen's request log.
        static let log = GatewayLabLog()
        private static let onEvent: @Sendable (APIEvent) -> Void = { event in
            let line = event.summary
            Task { @MainActor in log.append(line) }
        }
    #else
        private static let onEvent: @Sendable (APIEvent) -> Void = { _ in }
    #endif

    /// The fakes, when the real services aren't configured.
    static let fake: FakeGateway? =
        settings.usesRealServices
        ? nil : FakeGateway(appVersion: appVersion, policy: RetryPolicy(requestTimeout: .seconds(5)), onEvent: onEvent)

    static let real = RealGateway.make(settings: settings, appVersion: appVersion, onEvent: onEvent)

    static let account: any AccountService = real?.account ?? fake?.account ?? UnavailableAccountService()

    /// Paid cloud work (Phase 24b): App Attest on a device with the real backend; the stand-in
    /// attester with the fake backend.
    static let paid: any PaidActionService = real?.paid ?? fake?.paid ?? UnavailablePaidActionService()

    #if DEBUG
        /// The fake backend's behaviours, for the gateway screen. Nil on the real services.
        static var labControls: GatewayLabControls? {
            guard let backend = fake?.backend else { return nil }
            let modes: [(String, String, FakeBackendMode, Int?)] = [
                ("normal", "Normal", .normal, nil),
                ("expiredToken", "Token expires on the way (once)", .expiredToken, 1),
                ("offline", "Offline", .offline, nil),
                ("connectionLost", "Connection drops mid-request (once)", .connectionLost, 1),
                ("rateLimited", "429, retry after 30 seconds", .rateLimited(retryAfterSeconds: 30), nil),
                ("rateLimitedShort", "429, retry after 2 seconds (once)", .rateLimited(retryAfterSeconds: 2), 1),
                ("serverErrorOnce", "500 once, then fine", .serverError, 1),
                ("serverError", "500 every time", .serverError, nil),
                ("unavailable", "503, retry after 60 seconds", .unavailable(retryAfterSeconds: 60), nil),
                ("unavailableNoHint", "503, no Retry-After", .unavailable(retryAfterSeconds: nil), nil),
                ("forbidden", "403 forbidden", .forbidden, nil),
                ("slow", "Slow (3 seconds)", .slow(seconds: 3), nil),
                ("timeout", "Never answers (times out)", .timeout, nil),
                ("malformedJSON", "Malformed JSON", .malformedJSON, nil),
            ]
            let byID = Dictionary(uniqueKeysWithValues: modes.map { ($0.0, ($0.2, $0.3)) })
            return GatewayLabControls(
                modes: modes.map { .init(id: $0.0, title: $0.1) },
                setMode: { id in
                    guard let (mode, times) = byID[id] else { return }
                    backend.setMode(mode, times: times)
                })
        }

        /// The fake backend's limits, for the limits screen (Phase 24b). Nil on the real services,
        /// where the switches are Jose's (`npx convex run controls:setSwitch`).
        static var limitsControls: LimitsLabControls? {
            guard let backend = fake?.backend else { return nil }
            return LimitsLabControls(
                setPaused: { feature, paused in backend.setPaused(feature.rawValue, paused) },
                loseNextAnswer: { backend.setMode(.answerLost, times: 1) },
                jobsRun: { backend.paidJobsRun },
                resetUsage: { backend.resetUsage() })
        }
    #endif
}
