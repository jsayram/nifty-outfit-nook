import Foundation

// The 24b bodies: usage, App Attest registration and the placeholder paid actions. Same rules as
// APIV1.swift: these mirror contract.json, and the contract tests check them against its examples.

extension APIV1 {
    /// A contract date-time: decoded leniently, written with milliseconds as the backend writes it.
    public struct DateTime: Codable, Sendable, Equatable {
        public var date: Date

        public init(_ date: Date) { self.date = date }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = APIV1.parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date-time")
            }
            self.date = date
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(APIV1.formatDate(date))
        }
    }

    public struct UsageCategory: Codable, Sendable, Equatable {
        public var category: String
        public var usedToday: Int
        public var limitToday: Int
        public var usedThisMonth: Int
        public var limitThisMonth: Int
        public var resetsAt: DateTime?
    }

    public struct FeatureState: Codable, Sendable, Equatable {
        public var feature: String
        public var state: String
    }

    public struct Usage: Codable, Sendable, Equatable {
        public var categories: [UsageCategory]
        public var features: [FeatureState]
        public var policyVersion: Int
        /// 30b: her picture-credit balance. Optional here so an older backend still decodes.
        public var credits: CreditBalance?
        /// 30c: the server's view of styling access. Absent from older backends.
        public var styling: StylingAccess?
    }

    public struct AttestChallenge: Codable, Sendable, Equatable {
        public var challenge: String
        public var expiresAt: DateTime
    }

    public struct AttestKeyRequest: Codable, Sendable, Equatable {
        public var keyId: String
        public var attestation: String
        public var challenge: String
    }

    public struct AttestKeyResponse: Codable, Sendable, Equatable {
        public var keyId: String
        public var registeredAt: DateTime
    }

    public struct PaidAction: Codable, Sendable, Equatable {
        public var id: String
        public var kind: String
        public var status: String
        public var replayed: Bool
        public var createdAt: DateTime
    }

}
