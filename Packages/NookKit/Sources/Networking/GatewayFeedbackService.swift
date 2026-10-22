import Foundation
import Models

/// `FeedbackService` over the v1 gateway: POST /v1/feedback with the signed-in token. The same
/// code runs against the in-process fake backend and the real Convex deployment.
public struct GatewayFeedbackService: FeedbackService {
    private let auth: any AuthProvider
    private let client: APIClient

    public init(auth: any AuthProvider, client: APIClient) {
        self.auth = auth
        self.client = client
    }

    public func canSend() async -> Bool {
        await auth.isSignedIn()
    }

    public func send(_ submission: FeedbackSubmission) async throws(FeedbackSendProblem) -> FeedbackReceipt {
        do {
            let answer = try await client.send(
                APIV1.sendFeedback, body: APIV1.FeedbackRequest(submission), as: APIV1.FeedbackReceipt.self)
            return FeedbackReceipt(
                reference: answer.ticket.ref, receivedAt: APIV1.parseDate(answer.ticket.receivedAt) ?? Date(),
                hasScreenshot: answer.ticket.hasAttachment)
        } catch {
            throw Self.problem(for: error)
        }
    }

    static func problem(for failure: APIFailure) -> FeedbackSendProblem {
        switch failure {
        case .offline: .offline
        case .timedOut: .timedOut
        case .cancelled: .offline
        case .signedOut, .notRegistered: .signedOut
        case .forbidden: .rejected
        case .rateLimited(let seconds): .rateLimited(retryAfterSeconds: seconds)
        case .unavailable(let seconds): .unavailable(retryAfterSeconds: seconds)
        case .serverError: .serverError
        case .updateRequired: .updateRequired
        // The backend refuses a picture it can't use with invalid_request; so does a malformed
        // note, which the page's own checks stop first, so a rejection here is the picture.
        case .rejected: .screenshotRefused
        case .invalidResponse: .rejected
        // Paid-only answers; support never gets them.
        case .attestationRequired, .attestationUnavailable, .consentRequired, .idempotencyConflict: .rejected
        case .actionInProgress(let seconds), .actionRunning(_, let seconds): .unavailable(retryAfterSeconds: seconds)
        case .quotaExceeded(_, _, let seconds): .rateLimited(retryAfterSeconds: seconds)
        case .featurePaused(_, let seconds): .unavailable(retryAfterSeconds: seconds)
        }
    }
}
