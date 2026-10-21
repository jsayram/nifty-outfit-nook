import Foundation

// The 24c bodies: account deletion and its status. Same rules as APIV1.swift: these mirror
// contract.json, and the contract tests check them against its examples.

extension APIV1 {
    /// Safe to repeat: the backend returns the same deletion and carries on with it.
    public static let deleteAccount = Endpoint(
        id: "deleteAccount", method: "POST", path: "/v1/account/deletion", requiresAuth: true, idempotent: true)
    /// No token: the account, and its session, may already be gone. Reads only.
    public static let deletionStatus = Endpoint(
        id: "deletionStatus", method: "POST", path: "/v1/account/deletion/status", requiresAuth: false,
        idempotent: true)

    public struct DeletionRequest: Codable, Sendable, Equatable {
        public static let confirmation = "delete-my-account"
        public var confirm: String
        /// Apple's one-time authorization code from the fresh Sign in with Apple. Never stored.
        public var appleAuthorizationCode: String

        public init(appleAuthorizationCode: String) {
            confirm = Self.confirmation
            self.appleAuthorizationCode = appleAuthorizationCode
        }
    }

    public struct DeletionStatusRequest: Codable, Sendable, Equatable {
        public var deletionId: String

        public init(deletionId: String) { self.deletionId = deletionId }
    }

    public struct DeletionStep: Codable, Sendable, Equatable {
        public var step: String
        public var state: String
    }

    public struct Deletion: Codable, Sendable, Equatable {
        public var id: String
        public var state: String
        public var requestedAt: DateTime
        public var completedAt: DateTime?
        public var steps: [DeletionStep]
    }

    public struct DeletionStatus: Codable, Sendable, Equatable {
        public var deletion: Deletion
    }
}
