import Foundation
import Models

// F1b (D24): the opt-in analytics bodies, POST /v1/analytics/events and /v1/analytics/deletion.
// Same rules as APIV1.swift: these mirror contract.json, and the contract tests round-trip its
// golden examples through them.

extension APIV1 {
    /// One event as it travels. The hour is an ISO 8601 date-time at the start of a UTC hour.
    public struct AnalyticsRecord: Codable, Sendable, Equatable {
        public var event: String
        public var outcome: String
        public var hour: String
        public var appVersion: String
        public var systemVersion: String
        public var deviceClass: String
        public var consentVersion: String
        public var analyticsID: String

        public init(_ record: Models.AnalyticsRecord) {
            event = record.event.rawValue
            outcome = record.outcome.rawValue
            // Whole seconds: an hour has no fraction, and the backend takes either form.
            hour = record.hour.formatted(.iso8601)
            appVersion = record.appVersion
            systemVersion = record.systemVersion
            deviceClass = record.deviceClass.rawValue
            consentVersion = record.consentVersion
            analyticsID = record.analyticsID
        }
    }

    public struct AnalyticsBatch: Codable, Sendable, Equatable {
        public var events: [AnalyticsRecord]

        public init(_ records: [Models.AnalyticsRecord]) {
            events = records.map(AnalyticsRecord.init)
        }
    }

    /// How many events the server kept (events past its oldest hour aren't counted).
    public struct AnalyticsReceipt: Codable, Sendable, Equatable {
        public var accepted: Int
    }

    public struct AnalyticsDeletionRequest: Codable, Sendable, Equatable {
        public var analyticsID: String

        public init(analyticsID: String) {
            self.analyticsID = analyticsID
        }
    }

    /// Always `deleted: true`, whether the ID had events or not.
    public struct AnalyticsDeletionResponse: Codable, Sendable, Equatable {
        public var deleted: Bool
    }
}
