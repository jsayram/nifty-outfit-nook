import Foundation
import Models

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    // The fake backend's F1b half: POST /v1/analytics/events and /v1/analytics/deletion with the
    // real gateway's checks (convex/gateway/router.ts and convex/analytics.ts in the backend repo).
    // No token: a request carrying one, an App Attest key or an Idempotency-Key is refused, so a
    // client mistake shows here too. The per-ID and overall limits aren't modelled.

    /// One event the fake holds, as a test can read it.
    public struct FakeAnalyticsEvent: Sendable, Equatable {
        public var record: APIV1.AnalyticsRecord
        public var receivedAt: Date
    }

    struct FakeAnalytics {
        var events: [FakeAnalyticsEvent] = []
        var deletedIDs: [String] = []
    }

    extension FakeBackend {
        /// The backend's `consentVersions` and `oldestEventHours` (contract limits.analytics).
        static let analyticsConsentVersions: Set<String> = ["analytics-1"]
        private static let oldestAnalyticsEvent: TimeInterval = 192 * 3_600
        private static let accountHeaders = [
            "Authorization", "X-Nook-Attest-Key", "X-Nook-Assertion", "Idempotency-Key",
        ]

        // MARK: Controls for tests

        /// Every event the fake kept, oldest first.
        public var analyticsEvents: [FakeAnalyticsEvent] { state.withLock { $0.analytics.events } }

        /// Every analytics ID a deletion was asked for, oldest first.
        public var deletedAnalyticsIDs: [String] { state.withLock { $0.analytics.deletedIDs } }

        // MARK: Answering

        func routeAnalytics(_ request: URLRequest, body: Data?, endpoint: APIV1.Endpoint, id: String) -> FakeReply {
            if Self.accountHeaders.contains(where: { request.value(forHTTPHeaderField: $0) != nil }) {
                return error(.invalidRequest, id, message: "Send analytics without a sign-in token or device key.")
            }
            if let body, body.count > endpoint.maxBodyBytes { return error(.payloadTooLarge, id) }
            if endpoint == APIV1.deleteAnalytics {
                if let problem = checkJSON(request, body, fields: ["analyticsID"]) { return problem(id) }
                guard let body,
                    let decoded = try? JSONDecoder().decode(APIV1.AnalyticsDeletionRequest.self, from: body),
                    Self.isAnalyticsID(decoded.analyticsID)
                else { return error(.invalidRequest, id) }
                state.withLock { state in
                    state.analytics.events.removeAll { $0.record.analyticsID == decoded.analyticsID }
                    state.analytics.deletedIDs.append(decoded.analyticsID)
                }
                return encode(200, APIV1.AnalyticsDeletionResponse(deleted: true), id)
            }

            if let problem = checkJSON(request, body, fields: ["events"]) { return problem(id) }
            let fields: Set<String> = [
                "event", "outcome", "hour", "appVersion", "systemVersion", "deviceClass", "consentVersion",
                "analyticsID",
            ]
            guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                let raw = object["events"] as? [[String: Any]], raw.allSatisfy({ Set($0.keys) == fields }),
                let batch = try? JSONDecoder().decode(APIV1.AnalyticsBatch.self, from: body),
                !batch.events.isEmpty, batch.events.count <= 100,
                batch.events.allSatisfy(Self.isValid)
            else { return error(.invalidRequest, id) }
            let analyticsID = batch.events[0].analyticsID
            guard batch.events.allSatisfy({ $0.analyticsID == analyticsID }) else {
                return error(.invalidRequest, id, message: "Every event in a batch has the same analyticsID.")
            }
            guard batch.events.allSatisfy({ Self.analyticsConsentVersions.contains($0.consentVersion) }) else {
                return error(.consentRequired, id)
            }
            let time = now()
            var hours: [Date] = []
            for event in batch.events {
                guard let hour = APIV1.parseDate(event.hour),
                    hour.timeIntervalSince1970.truncatingRemainder(dividingBy: 3_600) == 0
                else { return error(.invalidRequest, id, message: "hour must be the start of an hour.") }
                if hour.timeIntervalSince(time) > 3_600 {
                    return error(.invalidRequest, id, message: "hour is in the future.")
                }
                hours.append(hour)
            }
            let kept = zip(batch.events, hours).filter { time.timeIntervalSince($0.1) <= Self.oldestAnalyticsEvent }
            state.withLock { state in
                state.analytics.events += kept.map { FakeAnalyticsEvent(record: $0.0, receivedAt: time) }
            }
            return encode(202, APIV1.AnalyticsReceipt(accepted: kept.count), id)
        }

        static func isAnalyticsID(_ text: String) -> Bool {
            text.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/) != nil
        }

        /// The contract's `AnalyticsRecord`: fixed lists and short versions only.
        static func isValid(_ e: APIV1.AnalyticsRecord) -> Bool {
            let version = /[0-9]{1,4}(\.[0-9]{1,4}){0,3}/
            return AnalyticsEvent(rawValue: e.event) != nil && AnalyticsOutcome(rawValue: e.outcome) != nil
                && AnalyticsDeviceClass(rawValue: e.deviceClass) != nil && e.hour.count <= 32
                && e.appVersion.wholeMatch(of: version) != nil && e.systemVersion.wholeMatch(of: version) != nil
                && e.consentVersion.wholeMatch(of: /[a-z0-9.-]{1,32}/) != nil && isAnalyticsID(e.analyticsID)
        }
    }
#endif
