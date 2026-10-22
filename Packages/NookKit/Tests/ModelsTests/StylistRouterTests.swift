import Foundation
import Models
import Testing

/// Phase 28's routing table: which stylist answers, and why the phone answers when it does.
struct StylistRouterTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var cloudSetUp = true
        var consent = true
        var connection = ConnectionState.online
        var model = OnDeviceModelStatus.deviceNotEligible
        var onDeviceStylist = false
        var lane: StylistLane
        var reason: QuickIdeasReason?

        var testDescription: String {
            "setUp \(cloudSetUp), consent \(consent), \(connection), model \(model), stylist \(onDeviceStylist)"
        }
    }

    static let table: [Row] = [
        // The cloud answers when it's set up, she agreed and the phone isn't known to be offline.
        Row(lane: .cloud, reason: nil),
        Row(connection: .unknown, lane: .cloud, reason: nil),
        Row(model: .available, onDeviceStylist: true, lane: .cloud, reason: nil),
        // Lily's iPhone 12: no on-device model, so the phone's answer is Quick ideas.
        Row(cloudSetUp: false, lane: .rules, reason: .cloudNotSetUp),
        Row(consent: false, lane: .rules, reason: .needsConsent),
        Row(connection: .offline, lane: .rules, reason: .offline),
        Row(consent: false, connection: .offline, lane: .rules, reason: .needsConsent),
        // A newer iPhone with the model and a stylist for it.
        Row(consent: false, model: .available, onDeviceStylist: true, lane: .onDevice, reason: .needsConsent),
        Row(connection: .offline, model: .available, onDeviceStylist: true, lane: .onDevice, reason: .offline),
        // The model is there but no stylist uses it (today), or it isn't ready: Quick ideas.
        Row(connection: .offline, model: .available, lane: .rules, reason: .offline),
        Row(connection: .offline, model: .modelNotReady, onDeviceStylist: true, lane: .rules, reason: .offline),
        Row(
            connection: .offline, model: .appleIntelligenceNotEnabled, onDeviceStylist: true, lane: .rules,
            reason: .offline),
        Row(connection: .offline, model: .unavailable, onDeviceStylist: true, lane: .rules, reason: .offline),
    ]

    @Test(arguments: table)
    func route(_ row: Row) {
        let conditions = StylistConditions(
            cloudSetUp: row.cloudSetUp, hasConsent: row.consent, connection: row.connection, onDeviceModel: row.model,
            hasOnDeviceStylist: row.onDeviceStylist)
        #expect(StylistRouter.route(conditions) == StylistRoute(lane: row.lane, reason: row.reason))
    }

    /// After the cloud tried: every refusal or failure falls back to the phone with its reason;
    /// her Cancel and a changed request don't.
    @Test(arguments: [
        (StylistError.offline, QuickIdeasReason?.some(.offline)),
        (.needsConsent, .needsConsent),
        (.limited(.needsConsent), .needsConsent),
        (
            .limited(.paused(feature: .style, retryAfterSeconds: nil)),
            .limited(.paused(feature: .style, retryAfterSeconds: nil))
        ),
        (
            .limited(.quotaExceeded(category: .styleFull, resetAt: Date(timeIntervalSince1970: 1_800_000_000))),
            .limited(.quotaExceeded(category: .styleFull, resetAt: Date(timeIntervalSince1970: 1_800_000_000)))
        ),
        (.limited(.rateLimited(retryAfterSeconds: 5)), .limited(.rateLimited(retryAfterSeconds: 5))),
        (.limited(.didNotFinish(retryAfterSeconds: 30)), .cloudDidNotFinish),
        (.notCompleted, .cloudDidNotFinish),
        (.timedOut, .cloudDidNotFinish),
        (.cancelled, nil),
        (.invalidRequest(.suitcaseNotFound), nil),
    ])
    func fallbackAfterTheCloud(_ error: StylistError, _ reason: QuickIdeasReason?) {
        let iPhone12 = StylistConditions(
            cloudSetUp: true, hasConsent: true, connection: .online, onDeviceModel: .deviceNotEligible)
        #expect(StylistRouter.fallback(after: error, iPhone12) == reason.map { StylistRoute(lane: .rules, reason: $0) })
        let newer = StylistConditions(
            cloudSetUp: true, hasConsent: true, connection: .online, onDeviceModel: .available,
            hasOnDeviceStylist: true)
        #expect(StylistRouter.fallback(after: error, newer)?.lane == (reason == nil ? nil : .onDevice))
    }

    /// The same for a cloud job (27c) that ended in a failure.
    @Test func fallbackAfterAJob() {
        #expect(StylistRouter.reason(after: AIJob.Failure.offline) == .offline)
        #expect(StylistRouter.reason(after: AIJob.Failure.notCompleted) == .cloudDidNotFinish)
        #expect(StylistRouter.reason(after: AIJob.Failure.needsConsent) == .needsConsent)
        #expect(
            StylistRouter.reason(after: AIJob.Failure.limited(.busy(retryAfterSeconds: 3)))
                == .limited(.busy(retryAfterSeconds: 3)))
        #expect(
            StylistRouter.reason(after: AIJob.Failure.limited(.didNotFinish(retryAfterSeconds: nil)))
                == .cloudDidNotFinish)
        #expect(StylistRouter.reason(after: AIJob.Failure.requestChanged) == nil)
    }
}
