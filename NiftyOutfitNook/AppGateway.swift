import ClerkAuth
import Features
import Foundation
import Models
import Networking
import Services

/// The app's one gateway to the backend (Phase 24a). With a Clerk publishable key and the backend
/// URL set (Configs/Secrets.xcconfig, docs/backend-switch.md) it signs in through Clerk and calls
/// the Convex deployment. Without them a Debug build runs on the fake sign-in and the in-process
/// fake backend. A Release build runs on neither: it fails closed (32b, L9), with every service
/// "unavailable" (signed out, nothing cloud works) and `cloudUnavailable` true, so the cloud
/// features say they aren't available right now. `FakeGateway` isn't compiled into Release at all.
/// Screens see only `AccountService` either way.
@MainActor
enum AppGateway {
    static let settings = GatewaySettings(info: Bundle.main.infoDictionary ?? [:])
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    /// Fakes exist only in Debug builds.
    #if DEBUG
        private static let allowsFakes = true
    #else
        private static let allowsFakes = false
    #endif
    static let mode = GatewayMode.resolve(settings: settings, allowsFakes: allowsFakes)

    /// True in a Release build with the backend settings missing. The services below are then the
    /// unavailable ones, and `NookServices.cloudUnavailable` tells the screens.
    static var cloudUnavailable: Bool { mode == .unavailable }

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

    #if DEBUG
        /// The fakes, when the real services aren't configured. Debug builds only.
        static let fake: FakeGateway? =
            mode == .fake
            ? FakeGateway(appVersion: appVersion, policy: RetryPolicy(requestTimeout: .seconds(5)), onEvent: onEvent)
            : nil
    #endif

    static let real = RealGateway.make(settings: settings, appVersion: appVersion, onEvent: onEvent)

    static let account: any AccountService = {
        if let real { return real.account }
        #if DEBUG
            if let fake { return fake.account }
        #endif
        return UnavailableAccountService()
    }()

    /// Send feedback's support queue (Phase 24d): the real backend, or the fake one. It takes notes
    /// only while she's signed in; signed out, Send feedback uses the share sheet.
    static let feedback: any FeedbackService = {
        if let real { return real.feedback }
        #if DEBUG
            if let fake { return fake.feedback }
        #endif
        return UnavailableFeedbackService()
    }()

    /// 30b: picture-credit claims, on the real backend or the fake one.
    static let credits: any CreditClaiming = {
        if let real { return real.credits }
        #if DEBUG
            if let fake { return fake.credits }
        #endif
        return UnavailableCreditClaimer()
    }()

    /// 30c: the subscription's and the unlock's signed transactions, sent to the same backend.
    static let stylingAccess: any StylingAccessClaiming = {
        if let real { return real.credits }
        #if DEBUG
            if let fake { return fake.credits }
        #endif
        return UnavailableCreditClaimer()
    }()

    /// The website's support page, from `NOOK_SUPPORT_URL` (a placeholder address until 35b).
    static let supportLinks = SupportLinks(info: Bundle.main.infoDictionary ?? [:])

    /// Paid cloud work (Phase 24b): App Attest on a device with the real backend; the stand-in
    /// attester with the fake backend.
    static let paid: any PaidActionService = {
        if let real { return real.paid }
        #if DEBUG
            if let fake { return fake.paid }
        #endif
        return UnavailablePaidActionService()
    }()

    /// Send feedback's queue, its screenshot maker and the support page (Phase 24d).
    static func installSupport(into services: inout NookServices) {
        services.feedback = feedback
        services.screenshots = ScreenshotPreparer()
        services.supportLinks = supportLinks
    }

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

        /// `-fake-signed-in` (debug builds, fake backend only): signs in with the fake Apple
        /// sign-in at launch and runs one paid action, so the fake backend holds an account, a key
        /// and a paid action. Delete my account then shows in Privacy and terms. After each
        /// deletion request the fake backend's counts go to `tmp/fake-backend-deletions.json` in
        /// the app's container, so a check from outside can see the server side ran (24c).
        static func signInIfAsked(arguments: [String]) async {
            guard arguments.contains("-fake-signed-in"), let fake else { return }
            let report = FileManager.default.temporaryDirectory.appending(path: "fake-backend-deletions.json")
            fake.backend.observeDeletions { data in try? data.write(to: report, options: .atomic) }
            // 24d: what the support queue received, for a check from outside the app.
            let support = FileManager.default.temporaryDirectory.appending(path: "fake-backend-support.json")
            fake.backend.observeSupport { data in try? data.write(to: support, options: .atomic) }
            _ = try? await fake.account.signIn()
            _ = try? await fake.paid.run(
                .style(.sample(.full, note: "debug")), idempotencyKey: IdempotencyKey.make())
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
