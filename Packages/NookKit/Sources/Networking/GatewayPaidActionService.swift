import Foundation
import Models

/// `PaidActionService` over the v1 gateway (24b): GET /v1/usage, and the paid endpoints with an
/// Idempotency-Key and an App Attest assertion on every try. The same code runs against the fake
/// backend and the real one.
public struct GatewayPaidActionService: PaidActionService {
    private let client: APIClient
    private let attestation: AttestationSession

    public init(client: APIClient, attestation: AttestationSession) {
        self.client = client
        self.attestation = attestation
    }

    public func usage() async throws(CloudLimitProblem) -> CloudUsage {
        do {
            return Self.usage(try await client.send(APIV1.usage, as: APIV1.Usage.self))
        } catch {
            throw Self.problem(for: error, paid: false)
        }
    }

    public func run(_ request: PaidActionRequest, idempotencyKey: String) async throws(CloudLimitProblem)
        -> PaidActionReceipt
    {
        do {
            return try await send(request, idempotencyKey: idempotencyKey)
        } catch .attestationRequired {
            // The backend didn't accept this install's key: register a new one and try once more,
            // with the same key, so it still can't run twice.
            await attestation.reset()
            do {
                return try await send(request, idempotencyKey: idempotencyKey)
            } catch {
                throw Self.problem(for: error)
            }
        } catch {
            throw Self.problem(for: error)
        }
    }

    private func send(_ request: PaidActionRequest, idempotencyKey: String) async throws(APIFailure)
        -> PaidActionReceipt
    {
        switch request {
        case .style(let call):
            let response = try await client.send(
                APIV1.style, body: APIV1.StyleRequest(call), idempotencyKey: idempotencyKey, signer: attestation,
                as: APIV1.StyleResponse.self)
            guard let usage = Self.allowance(response.usage), let answer = response.result.styleAnswer else {
                throw .invalidResponse
            }
            return PaidActionReceipt(
                id: response.action.id, feature: .style, replayed: response.action.replayed, usage: usage, style: answer)
        case .tryOn(let revision):
            let response = try await client.send(
                APIV1.tryOn, body: APIV1.TryOnRequest(contextRevision: revision),
                idempotencyKey: idempotencyKey, signer: attestation, as: APIV1.PaidActionResponse.self)
            guard let usage = Self.allowance(response.usage) else { throw .invalidResponse }
            return PaidActionReceipt(
                id: response.action.id, feature: .tryOn, replayed: response.action.replayed, usage: usage)
        }
    }

    static func allowance(_ body: APIV1.UsageCategory) -> UsageAllowance? {
        guard let category = UsageCategory(rawValue: body.category) else { return nil }
        return UsageAllowance(
            category: category, usedToday: body.usedToday, limitToday: body.limitToday,
            usedThisMonth: body.usedThisMonth, limitThisMonth: body.limitThisMonth, resetsAt: body.resetsAt?.date)
    }

    static func usage(_ body: APIV1.Usage) -> CloudUsage {
        CloudUsage(
            allowances: body.categories.compactMap(allowance),
            paused: Set(body.features.filter { $0.state != "on" }.compactMap { PaidFeature(rawValue: $0.feature) }))
    }

    static func problem(for failure: APIFailure, paid: Bool = true, now: Date = Date()) -> CloudLimitProblem {
        switch failure {
        case .rateLimited(let seconds):
            .rateLimited(retryAfterSeconds: seconds)
        case .quotaExceeded(let category, let resetAt, let seconds):
            .quotaExceeded(
                category: UsageCategory(rawValue: category) ?? .monthlySpend,
                resetAt: resetAt ?? now.addingTimeInterval(TimeInterval(seconds)))
        case .featurePaused(let feature, let seconds):
            .paused(feature: feature.flatMap(PaidFeature.init(rawValue:)), retryAfterSeconds: seconds)
        case .actionInProgress(let seconds):
            .busy(retryAfterSeconds: seconds)
        case .attestationRequired, .attestationUnavailable:
            .deviceNotVerified
        case .consentRequired:
            .needsConsent
        case .unavailable(let seconds) where paid:
            // From a paid endpoint: the job failed, or its outcome is still being checked.
            .didNotFinish(retryAfterSeconds: seconds)
        default:
            .account(GatewayAccountService.problem(for: failure))
        }
    }
}
