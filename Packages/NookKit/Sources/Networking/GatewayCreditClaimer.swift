import Foundation
import Models

/// `CreditClaiming` over the v1 gateway (30b): POST /v1/credits/claim with the signed-in token,
/// and 30c's `StylingAccessClaiming`: POST /v1/entitlements/claim. The same code runs against the
/// fake backend and the real one. No App Attest: the signed transaction is the proof, and a claim
/// costs nothing.
public struct GatewayCreditClaimer: CreditClaiming, StylingAccessClaiming {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func claim(signedTransaction: String) async throws(CreditClaimProblem) -> CreditClaim {
        do {
            let answer = try await client.send(
                APIV1.claimCredits, body: APIV1.CreditClaimRequest(signedTransaction: signedTransaction),
                as: APIV1.CreditClaimResponse.self)
            return CreditClaim(
                transactionID: answer.claim.transactionId, pictures: answer.claim.pictures,
                replayed: answer.claim.replayed, balance: answer.credits.pictures)
        } catch {
            throw Self.problem(for: error)
        }
    }

    public func claimStylingAccess(signedTransaction: String) async throws(CreditClaimProblem) -> Bool {
        do {
            let answer = try await client.send(
                APIV1.claimEntitlement, body: APIV1.EntitlementClaimRequest(signedTransaction: signedTransaction),
                as: APIV1.EntitlementClaimResponse.self)
            return answer.styling.access
        } catch {
            throw Self.problem(for: error)
        }
    }

    static func problem(for failure: APIFailure) -> CreditClaimProblem {
        switch failure {
        case .offline, .timedOut, .cancelled: .offline
        case .signedOut, .notRegistered: .signedOut
        case .forbidden, .rejected: .rejected
        case .rateLimited, .unavailable, .actionInProgress, .quotaExceeded, .featurePaused: .unavailable
        case .serverError, .updateRequired, .invalidResponse, .attestationRequired, .attestationUnavailable,
            .consentRequired, .idempotencyConflict:
            .failed
        }
    }
}
