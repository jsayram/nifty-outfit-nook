import Foundation

// The 35 bodies: POST /v1/actions/status. Same rules as APIV1.swift: these mirror contract.json,
// and the contract tests round-trip its golden examples through them.
//
// While a try-on picture is made, the app asks where the action stands with only the action's ID
// (from error.actionId of the first 409), never by sending the photos again.

extension APIV1 {
    public struct ActionStatusRequest: Codable, Sendable, Equatable {
        public var actionId: String

        public init(actionId: String) {
            self.actionId = actionId
        }
    }

    public struct ActionState: Codable, Sendable, Equatable {
        public var id: String
        public var kind: String
        /// "running", "succeeded", "failed" or "expired". An unknown word is treated as running.
        public var status: String
        public var createdAt: DateTime
        /// Only while running: seconds to wait before asking again.
        public var retryAfterSeconds: Int?
    }

    public struct ActionStatusResponse: Codable, Sendable, Equatable {
        public var action: ActionState
        /// A finished stylist action's answer, shaped as `StyleResponse.result`.
        public var styleResult: StylistResult?
        /// A finished try-on's picture, shaped as `TryOnResponse.result`.
        public var tryOnResult: TryOnResult?
        public var usage: UsageCategory?
    }
}
