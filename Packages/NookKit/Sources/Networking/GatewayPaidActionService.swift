import Foundation
import Models

/// `PaidActionService` over the v1 gateway (24b): GET /v1/usage, and the paid endpoints with an
/// Idempotency-Key and an App Attest assertion on every try. The same code runs against the fake
/// backend and the real one.
public struct GatewayPaidActionService: PaidActionService {
    private let client: APIClient
    private let attestation: AttestationSession
    /// 30a: the subscription hint on every paid request. Only a hint; the server decides (30c).
    private let entitlementHint: EntitlementHintSource

    public init(
        client: APIClient, attestation: AttestationSession, entitlementHint: EntitlementHintSource = .shared
    ) {
        self.client = client
        self.attestation = attestation
        self.entitlementHint = entitlementHint
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
        let signer = HintedSigner(base: attestation, hint: entitlementHint.current)
        switch request {
        case .style(let call):
            let response = try await client.send(
                APIV1.style, body: APIV1.StyleRequest(call), idempotencyKey: idempotencyKey, signer: signer,
                as: APIV1.StyleResponse.self)
            guard let usage = Self.allowance(response.usage), let answer = response.result.styleAnswer else {
                throw .invalidResponse
            }
            return PaidActionReceipt(
                id: response.action.id, feature: .style, replayed: response.action.replayed, usage: usage, style: answer
            )
        case .tryOn(let call):
            // 33a: the first answer is "still running" (409); the client asks again with the same
            // key and body until the picture comes back, within try-on's 360-second deadline.
            let response = try await client.send(
                APIV1.tryOn, body: APIV1.TryOnRequest(call), idempotencyKey: idempotencyKey, signer: signer,
                as: APIV1.TryOnResponse.self)
            guard let usage = Self.allowance(response.usage), let image = response.result.image.bytes else {
                throw .invalidResponse
            }
            return PaidActionReceipt(
                id: response.action.id, feature: .tryOn, replayed: response.action.replayed, usage: usage,
                tryOnImage: image)
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
            paused: Set(body.features.filter { $0.state != "on" }.compactMap { PaidFeature(rawValue: $0.feature) }),
            credits: body.credits?.pictures)
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
