import Foundation
import Models

/// `AnalyticsEndpoint` over the v1 gateway (F1c, D24). Both calls go without an account token, an
/// App Attest key or an Idempotency-Key: the endpoints don't require auth, so `APIClient` adds
/// none, and the backend refuses a request that carries one. The analytics ID is the only key.
public struct GatewayAnalyticsEndpoint: AnalyticsEndpoint {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func send(_ records: [Models.AnalyticsRecord]) async throws {
        guard !records.isEmpty else { return }
        do {
            _ = try await client.send(
                APIV1.sendAnalytics, body: APIV1.AnalyticsBatch(records), as: APIV1.AnalyticsReceipt.self)
        } catch {
            throw Self.error(for: error)
        }
    }

    public func deleteEvents(analyticsID: String) async throws {
        let answer = try await client.send(
            APIV1.deleteAnalytics, body: APIV1.AnalyticsDeletionRequest(analyticsID: analyticsID),
            as: APIV1.AnalyticsDeletionResponse.self)
        guard answer.deleted else { throw APIFailure.invalidResponse }
    }

    /// A refusal that sending again can't change drops the batch; anything else keeps it.
    static func error(for failure: APIFailure) -> any Error {
        switch failure {
        case .rejected, .consentRequired: AnalyticsBatchRefused()
        default: failure
        }
    }
}
