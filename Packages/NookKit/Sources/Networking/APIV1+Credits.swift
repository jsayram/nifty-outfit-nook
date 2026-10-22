import Foundation

// The 30b bodies: picture credits. Same rules as APIV1.swift: these mirror contract.json, and the
// contract tests check them against its examples.

extension APIV1 {
    public struct CreditBalance: Codable, Sendable, Equatable {
        public var pictures: Int
    }

    /// The App Store transaction's signed JWS, as StoreKit gives it. The server reads the
    /// transaction and product from it; the app sends nothing else.
    public struct CreditClaimRequest: Codable, Sendable, Equatable {
        public var signedTransaction: String
    }

    public struct CreditClaimResponse: Codable, Sendable, Equatable {
        public struct Claim: Codable, Sendable, Equatable {
            public var transactionId: String
            public var productId: String
            public var pictures: Int
            public var replayed: Bool
            public var claimedAt: DateTime
        }

        public var claim: Claim
        public var credits: CreditBalance
    }

    // 30c

    /// The subscription's or the complimentary unlock's signed JWS, as StoreKit gives it.
    public typealias EntitlementClaimRequest = CreditClaimRequest

    /// The server's own view of her styling access, from Apple's verified records only.
    public struct StylingAccess: Codable, Sendable, Equatable {
        public var access: Bool
        /// subscription, unlock, plan or none.
        public var source: String
        public var expiresAt: DateTime?
    }

    public struct EntitlementClaimResponse: Codable, Sendable, Equatable {
        public var productId: String
        public var styling: StylingAccess
    }
}
