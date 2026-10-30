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
        try await run(request, idempotencyKey: idempotencyKey, link: .none)
    }

    /// The request is sent once. If the server says it is running and names the action, from then
    /// on only the action's ID is sent (Phase 35), so a try-on's photos go up one time however
    /// long the picture takes. With `link.resume` (a relaunch, or a late answer) it starts there.
    public func run(_ request: PaidActionRequest, idempotencyKey: String, link: ActionLink)
        async throws(CloudLimitProblem) -> PaidActionReceipt
    {
        do {
            if let resumed = link.resume {
                do {
                    return try await follow(resumed, request, wait: .zero)
                } catch .rejected(code: APIV1.ErrorCode.notFound.rawValue) {
                    // The server doesn't have that action any more: ask the old way, once, with the
                    // same key. It answers from its record, or starts the action again.
                }
            }
            return try await sendAndFollow(request, idempotencyKey: idempotencyKey, link: link)
        } catch {
            throw Self.problem(for: error)
        }
    }

    private func sendAndFollow(_ request: PaidActionRequest, idempotencyKey: String, link: ActionLink)
        async throws(APIFailure) -> PaidActionReceipt
    {
        do {
            do {
                return try await send(request, idempotencyKey: idempotencyKey)
            } catch .attestationRequired {
                // The backend didn't accept this install's key: register a new one and try once
                // more, with the same key, so it still can't run twice.
                await attestation.reset()
                return try await send(request, idempotencyKey: idempotencyKey)
            }
        } catch .actionRunning(let actionID, let retryAfter) {
            link.started(actionID)
            return try await follow(actionID, request, wait: .seconds(min(max(retryAfter, 1), 10)))
        }
    }

    /// Asks for the action's status until it has finished, then turns the answer into a receipt.
    private func follow(_ actionID: String, _ request: PaidActionRequest, wait: Duration)
        async throws(APIFailure) -> PaidActionReceipt
    {
        let paid = request.feature == .style ? APIV1.style : APIV1.tryOn
        let response = try await client.awaitAction(actionID, firstAskAfter: wait, deadlineOf: paid)
        switch response.action.status {
        case "succeeded":
            guard let usage = response.usage.flatMap(Self.allowance) else { throw .invalidResponse }
            switch request {
            case .style:
                guard let answer = response.styleResult?.styleAnswer else { throw .invalidResponse }
                return PaidActionReceipt(
                    id: response.action.id, feature: .style, replayed: false, usage: usage, style: answer)
            case .tryOn:
                guard let image = response.tryOnResult?.image.bytes else { throw .invalidResponse }
                return PaidActionReceipt(
                    id: response.action.id, feature: .tryOn, replayed: false, usage: usage, tryOnImage: image)
            }
        case "failed":
            // Nothing was counted. A new tap is a new action with a new key.
            throw .unavailable(retryAfterSeconds: 30)
        default:
            // Expired: it was made, but the picture is no longer kept.
            throw .unavailable(retryAfterSeconds: nil)
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
            // 33a: the first answer is "still running" (409, 35: with the action's ID). The
            // caller then follows it by ID, within try-on's 360-second deadline. A 200 here is the
            // picture, for a request that was already done.
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
        case .actionInProgress(let seconds), .actionRunning(_, let seconds):
            .busy(retryAfterSeconds: seconds)
        case .attestationRequired, .attestationUnavailable:
            .deviceNotVerified
        case .consentRequired:
            .needsConsent
        case .entitlementRequired:
            .needsStylingAccess
        case .unavailable(let seconds) where paid:
            // From a paid endpoint: the job failed, or its outcome is still being checked.
            .didNotFinish(retryAfterSeconds: seconds)
        default:
            .account(GatewayAccountService.problem(for: failure))
        }
    }
}
