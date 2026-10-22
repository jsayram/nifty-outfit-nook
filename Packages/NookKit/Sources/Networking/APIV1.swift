import Foundation

/// Version 1 of the app-to-backend API, as Swift types. The source of truth is
/// `contract/v1/contract.json` in the private backend repo; `NetworkingTests/Contract` holds a
/// byte-identical copy, and the contract tests check these types against its golden examples.
///
/// No type here names an AI provider or model. Later endpoints ask the backend to do a job, and
/// the backend picks who does it.
public enum APIV1 {
    public static let version = 1
    public static let maxBodyBytes = 65_536

    /// One endpoint: its method, path, whether it needs a token, and whether repeating it is safe,
    /// so the client may retry it after a timeout or a 5xx.
    public struct Endpoint: Sendable, Hashable {
        public var id: String
        public var method: String
        public var path: String
        public var requiresAuth: Bool
        public var idempotent: Bool
        /// Paid endpoints need an Idempotency-Key and an App Attest assertion (24b).
        public var paid = false
        /// The most a request body may hold. The contract's 64 KiB, except for the one endpoint
        /// that carries a screenshot (24d).
        public var maxBodyBytes = APIV1.maxBodyBytes
    }

    public static let health = Endpoint(
        id: "health", method: "GET", path: "/v1/health", requiresAuth: false, idempotent: true)
    /// Safe to repeat: a second call returns the same account with `newAccount` false.
    public static let createSession = Endpoint(
        id: "createSession", method: "POST", path: "/v1/session", requiresAuth: true, idempotent: true)
    public static let me = Endpoint(id: "me", method: "GET", path: "/v1/me", requiresAuth: true, idempotent: true)

    // 24b
    public static let usage = Endpoint(
        id: "usage", method: "GET", path: "/v1/usage", requiresAuth: true, idempotent: true)
    /// Not repeated on its own: each call makes a new one-time challenge.
    public static let attestChallenge = Endpoint(
        id: "attestChallenge", method: "POST", path: "/v1/attest/challenge", requiresAuth: true, idempotent: false)
    /// Not repeated on its own: a challenge works once.
    public static let attestKey = Endpoint(
        id: "attestKey", method: "POST", path: "/v1/attest/key", requiresAuth: true, idempotent: false)
    /// Safe to repeat because every try carries the same Idempotency-Key: the server answers a
    /// repeat with the first result, without running or counting it again.
    public static let style = Endpoint(
        id: "style", method: "POST", path: "/v1/style", requiresAuth: true, idempotent: true, paid: true)
    public static let tryOn = Endpoint(
        id: "tryOn", method: "POST", path: "/v1/try-on", requiresAuth: true, idempotent: true, paid: true)

    public static let endpoints = [
        health, createSession, me, usage, attestChallenge, attestKey, style, tryOn, deleteAccount, deletionStatus,
        sendFeedback,
    ]

    // MARK: Bodies

    public struct Health: Codable, Sendable, Equatable {
        public var status: String
        public var apiVersion: Int
    }

    public struct SessionRequest: Codable, Sendable, Equatable {
        public var platform: String
        public var appVersion: String

        public init(platform: String = "ios", appVersion: String) {
            self.platform = platform
            self.appVersion = appVersion
        }
    }

    public struct User: Codable, Sendable, Equatable {
        public var id: String
        public var createdAt: Date

        enum CodingKeys: String, CodingKey { case id, createdAt }

        public init(id: String, createdAt: Date) {
            self.id = id
            self.createdAt = createdAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            let text = try container.decode(String.self, forKey: .createdAt)
            guard let date = APIV1.parseDate(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .createdAt, in: container, debugDescription: "Not an ISO 8601 date-time")
            }
            createdAt = date
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(APIV1.formatDate(createdAt), forKey: .createdAt)
        }
    }

    public struct SessionResponse: Codable, Sendable, Equatable {
        public var user: User
        public var newAccount: Bool
    }

    public struct Me: Codable, Sendable, Equatable {
        public var user: User
    }

    /// Every error response's body.
    public struct ErrorEnvelope: Codable, Sendable, Equatable {
        public struct Body: Codable, Sendable, Equatable {
            public var code: String
            public var message: String
            public var requestId: String
            public var retryAfterSeconds: Int?
            /// quota_exceeded: which allowance.
            public var category: String?
            /// quota_exceeded: when the next one frees up, as the contract's date-time text.
            public var resetAt: String?
            /// feature_paused: which feature.
            public var feature: String?
        }
        public var error: Body
    }

    /// The error codes in the contract. The client treats a code it doesn't know by its HTTP
    /// status, so the backend can add codes without breaking older apps.
    public enum ErrorCode: String, Sendable, CaseIterable {
        case invalidRequest = "invalid_request"
        case unauthenticated
        case tokenExpired = "token_expired"
        case forbidden
        case notFound = "not_found"
        case notRegistered = "not_registered"
        case methodNotAllowed = "method_not_allowed"
        case apiVersionRetired = "api_version_retired"
        case payloadTooLarge = "payload_too_large"
        case unsupportedMediaType = "unsupported_media_type"
        case rateLimited = "rate_limited"
        case `internal`
        case unavailable
        // 24b
        case attestationRequired = "attestation_required"
        case idempotencyConflict = "idempotency_conflict"
        case actionInProgress = "action_in_progress"
        case quotaExceeded = "quota_exceeded"
        case featurePaused = "feature_paused"
        // 27a
        case consentRequired = "consent_required"

        /// The HTTP status the contract gives each code.
        public var status: Int {
            switch self {
            case .invalidRequest: 400
            case .unauthenticated, .tokenExpired: 401
            case .forbidden, .attestationRequired, .consentRequired: 403
            case .notFound, .notRegistered: 404
            case .methodNotAllowed: 405
            case .idempotencyConflict, .actionInProgress: 409
            case .apiVersionRetired: 410
            case .payloadTooLarge: 413
            case .unsupportedMediaType: 415
            case .rateLimited, .quotaExceeded: 429
            case .internal: 500
            case .unavailable, .featurePaused: 503
            }
        }
    }

    // MARK: Dates

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecondStyle = Date.ISO8601FormatStyle()

    /// The contract's date-times: ISO 8601 in UTC, with or without fractional seconds.
    public static func parseDate(_ text: String) -> Date? {
        (try? dateStyle.parse(text)) ?? (try? wholeSecondStyle.parse(text))
    }

    /// Always with milliseconds, as the backend writes them ("2026-10-21T03:00:00.000Z").
    public static func formatDate(_ date: Date) -> String {
        dateStyle.format(date)
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
