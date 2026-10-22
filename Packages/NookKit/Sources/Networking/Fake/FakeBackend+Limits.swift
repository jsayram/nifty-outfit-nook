import CryptoKit
import Foundation

// The fake backend's 24b half: usage, App Attest registration and the placeholder paid endpoints,
// checked in the real gateway's order (convex/ledger.ts in the backend repo): the Idempotency-Key
// and body, the assertion, idempotency, the switches, the rate limit, then the allowance. It keeps
// no money: the spending ceilings are the real backend's job, and the fake shows them only as a
// paused feature.

/// The limits the fake enforces. The defaults are the backend's policy (convex/limits/policy.ts).
public struct FakeLimits: Sendable, Equatable {
    public var rateCapacity = 5
    public var rateSeconds: Double = 60
    public var allowances: [String: (day: Int, month: Int)] = [
        "styleFull": (10, 150), "styleQuick": (40, 600), "tryOn": (3, 30),
    ]
    /// Features switched off, as the server's kill switch or a spending ceiling would.
    public var paused: Set<String> = []
    /// 27a: how the stand-in stylist behaves.
    public var stylist = FakeStylistBehaviour.normal

    public init() {}

    public static func == (a: FakeLimits, b: FakeLimits) -> Bool {
        a.rateCapacity == b.rateCapacity && a.rateSeconds == b.rateSeconds && a.paused == b.paused
            && a.stylist == b.stylist
            && a.allowances.mapValues { [$0.day, $0.month] } == b.allowances.mapValues { [$0.day, $0.month] }
    }
}

struct FakeLedger {
    struct Action {
        var id: String
        var subject: String
        var fingerprint: Data
        var feature: String
        var category: String
        var createdAt: Date
        /// 27a: false for an answer that needed no provider call (from the result cache, or
        /// pieces that can't make an outfit). It uses no allowance, like the backend's noCharge.
        var counted = true
        /// 27a: the stylist's answer, for a replay of the same key.
        var style: APIV1.StylistResult?
    }

    var challenges: [String: (subject: String, expiresAt: Date, used: Bool)] = [:]
    var keys: [String: (subject: String, publicKey: P256.Signing.PublicKey, counter: UInt32)] = [:]
    var buckets: [String: (tokens: Double, updatedAt: Date)] = [:]
    /// By "<subject> <Idempotency-Key>".
    var actions: [String: Action] = [:]
    /// How many paid jobs actually ran: a replay or a cached answer doesn't add one.
    var jobsRun = 0
    /// 27a: the result cache, by account and normalized request, for 24 hours.
    var styleCache: [String: (result: APIV1.StylistResult, at: Date)] = [:]
}

extension FakeBackend {
    // MARK: Controls for tests and the debug screen

    /// Switches a paid feature ("style" or "tryOn") off or on, like the server's kill switch.
    public func setPaused(_ feature: String, _ paused: Bool) {
        state.withLock {
            if paused { $0.limits.paused.insert(feature) } else { $0.limits.paused.remove(feature) }
        }
    }

    /// Changes one category's allowances ("styleFull", "styleQuick", "tryOn").
    public func setAllowance(_ category: String, day: Int, month: Int) {
        state.withLock { $0.limits.allowances[category] = (day, month) }
    }

    public var limits: FakeLimits { state.withLock { $0.limits } }

    /// 27a: how the stand-in stylist behaves from now on.
    public func setStylist(_ behaviour: FakeStylistBehaviour) {
        state.withLock { $0.limits.stylist = behaviour }
    }

    /// 30a: the `X-Nook-Entitlement-Hint` of the last paid request, as sent. Like the real
    /// backend until 30c, the fake never admits or refuses anything because of it.
    public var lastEntitlementHint: String? { state.withLock { $0.lastEntitlementHint } }

    /// Paid jobs that really ran. A retry the backend answered from its record doesn't count.
    public var paidJobsRun: Int { state.withLock { $0.ledger.jobsRun } }

    /// 27c: paid actions admitted, one per Idempotency-Key. A new key is a new action, even when
    /// the result cache answers it; the same key again is the same action.
    public var paidActionCount: Int { state.withLock { $0.ledger.actions.count } }

    /// Forgets every paid action, rate bucket and allowance use (keys and accounts stay).
    public func resetUsage() {
        state.withLock {
            $0.ledger.actions = [:]
            $0.ledger.buckets = [:]
            $0.ledger.jobsRun = 0
            $0.ledger.styleCache = [:]
        }
    }

    // MARK: Routing

    func routeLimits(_ request: URLRequest, body: Data?, endpoint: APIV1.Endpoint, subject: String, id: String)
        -> FakeReply
    {
        switch endpoint {
        case APIV1.usage:
            return encode(200, usage(subject: subject), id)
        case APIV1.attestChallenge:
            let challenge = "chl_" + FakeToken.randomHex(16)
            let expiresAt = Self.millisecondPrecision(now().addingTimeInterval(300))
            state.withLock { $0.ledger.challenges[challenge] = (subject, expiresAt, false) }
            return encode(200, APIV1.AttestChallenge(challenge: challenge, expiresAt: .init(expiresAt)), id)
        case APIV1.attestKey:
            return registerKey(request, body: body, subject: subject, id: id)
        case APIV1.style, APIV1.tryOn:
            return paid(request, body: body, endpoint: endpoint, subject: subject, id: id)
        default:
            return error(.notFound, id)
        }
    }

    private func usage(subject: String) -> APIV1.Usage {
        state.withLock { state in
            APIV1.Usage(
                categories: ["styleFull", "styleQuick", "tryOn"].map {
                    snapshot(state, subject: subject, category: $0)
                },
                features: ["style", "tryOn"].map {
                    APIV1.FeatureState(feature: $0, state: state.limits.paused.contains($0) ? "paused" : "on")
                },
                policyVersion: 1, credits: .init(pictures: state.credits.balance(of: subject)))
        }
    }

    private func snapshot(_ state: State, subject: String, category: String) -> APIV1.UsageCategory {
        let allowance = state.limits.allowances[category] ?? (0, 0)
        let time = now()
        let times = state.ledger.actions.values
            .filter {
                $0.subject == subject && $0.category == category && $0.counted
                    && $0.createdAt > time.addingTimeInterval(-30 * 86_400)
            }
            .map(\.createdAt).sorted()
        let today = times.filter { $0 > time.addingTimeInterval(-86_400) }
        var resetsAt = today.first.map { $0.addingTimeInterval(86_400) }
        if times.count >= allowance.month {
            resetsAt = times[times.count - allowance.month].addingTimeInterval(30 * 86_400)
        } else if today.count >= allowance.day, allowance.day > 0 {
            resetsAt = today[today.count - allowance.day].addingTimeInterval(86_400)
        }
        return APIV1.UsageCategory(
            category: category, usedToday: today.count, limitToday: allowance.day, usedThisMonth: times.count,
            limitThisMonth: allowance.month, resetsAt: resetsAt.map(APIV1.DateTime.init))
    }

    private func registerKey(_ request: URLRequest, body: Data?, subject: String, id: String) -> FakeReply {
        guard let body, let parsed = try? JSONDecoder().decode(APIV1.AttestKeyRequest.self, from: body) else {
            return error(.invalidRequest, id)
        }
        guard let attestation = Data(base64Encoded: parsed.attestation),
            let document = try? JSONSerialization.jsonObject(with: attestation) as? [String: String],
            document["fmt"] == "nook-mock-v1", document["appId"] == FakeDeviceAttester.appID,
            document["clientDataHash"] == AttestClientData.hash(parsed.challenge).base64EncodedString(),
            let raw = document["publicKey"].flatMap({ Data(base64Encoded: $0) }),
            let publicKey = try? P256.Signing.PublicKey(x963Representation: raw),
            Data(SHA256.hash(data: raw)).base64EncodedString() == parsed.keyId
        else { return error(.attestationRequired, id) }
        let accepted = state.withLock { state -> Bool in
            guard let challenge = state.ledger.challenges[parsed.challenge], challenge.subject == subject,
                !challenge.used, challenge.expiresAt > now()
            else { return false }
            state.ledger.challenges[parsed.challenge]?.used = true
            if let existing = state.ledger.keys[parsed.keyId] { return existing.subject == subject }
            state.ledger.keys[parsed.keyId] = (subject, publicKey, 0)
            return true
        }
        guard accepted else { return error(.attestationRequired, id) }
        return encode(
            200, APIV1.AttestKeyResponse(keyId: parsed.keyId, registeredAt: .init(Self.millisecondPrecision(now()))), id
        )
    }

    private func paid(_ request: URLRequest, body: Data?, endpoint: APIV1.Endpoint, subject: String, id: String)
        -> FakeReply
    {
        guard let key = request.value(forHTTPHeaderField: "Idempotency-Key"),
            key.wholeMatch(of: /[A-Za-z0-9_-]{16,64}/) != nil
        else { return error(.invalidRequest, id, message: "Send an Idempotency-Key header.") }
        let hint = request.value(forHTTPHeaderField: EntitlementHintSource.header)
        state.withLock { $0.lastEntitlementHint = hint }
        guard (request.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().hasPrefix("application/json")
        else { return error(.unsupportedMediaType, id) }
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return error(.invalidRequest, id)
        }
        let feature = endpoint == APIV1.style ? "style" : "tryOn"
        var styleRequest: APIV1.StyleRequest?
        if feature == "style" {
            // 27a: the stylist's body, checked like the backend checks it, then her consent.
            guard let decoded = try? JSONDecoder().decode(APIV1.StyleRequest.self, from: body),
                FakeStylist.isValid(object, decoded: decoded)
            else { return error(.invalidRequest, id) }
            styleRequest = decoded
        } else {
            guard Set(object.keys) == ["contextRevision"],
                (object["contextRevision"] as? String)?.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil
            else { return error(.invalidRequest, id) }
        }
        let category = feature == "tryOn" ? "tryOn" : (styleRequest?.mode == "full" ? "styleFull" : "styleQuick")

        // App Attest, as the real gateway checks it.
        guard let keyID = request.value(forHTTPHeaderField: "X-Nook-Attest-Key"),
            let assertion = request.value(forHTTPHeaderField: "X-Nook-Assertion").flatMap({ Data(base64Encoded: $0) }),
            let counter = verify(
                assertion: assertion, keyID: keyID, subject: subject,
                clientData: AttestClientData.make(
                    method: endpoint.method, path: endpoint.path, idempotencyKey: key, body: body))
        else { return error(.attestationRequired, id) }

        if let styleRequest, !FakeStylist.consentVersions.contains(styleRequest.consentVersion) {
            return error(.consentRequired, id)
        }
        let fingerprint = Data(SHA256.hash(data: Data((endpoint.id + "\n").utf8) + body))
        // The result cache's key: the account and the request without the app's own revision.
        var cacheKey: String?
        if var normalized = styleRequest {
            normalized.contextRevision = ""
            normalized.closet.sort { $0.id < $1.id }
            if let data = try? APIV1.encoder().encode(normalized) {
                cacheKey = subject + " " + Data(SHA256.hash(data: data)).base64EncodedString()
            }
        }
        enum Outcome {
            case reply(FakeReply)
            case done(FakeLedger.Action, replayed: Bool, usage: APIV1.UsageCategory)
        }
        let outcome: Outcome = state.withLock { state in
            guard let stored = state.ledger.keys[keyID], stored.subject == subject, counter > stored.counter else {
                return .reply(error(.attestationRequired, id))
            }
            state.ledger.keys[keyID]?.counter = counter
            let actionKey = subject + " " + key
            if let existing = state.ledger.actions[actionKey] {
                guard existing.fingerprint == fingerprint else { return .reply(error(.idempotencyConflict, id)) }
                return .done(existing, replayed: true, usage: snapshot(state, subject: subject, category: category))
            }
            if state.limits.paused.contains(feature) {
                return .reply(error(.featurePaused, id, feature: feature))
            }
            // Token bucket.
            let time = now()
            let perSecond = Double(state.limits.rateCapacity) / state.limits.rateSeconds
            let bucket = state.ledger.buckets[subject] ?? (Double(state.limits.rateCapacity), time)
            let tokens = min(
                Double(state.limits.rateCapacity), bucket.tokens + time.timeIntervalSince(bucket.updatedAt) * perSecond)
            guard tokens >= 1 else {
                state.ledger.buckets[subject] = (tokens, time)
                return .reply(error(.rateLimited, id, retryAfter: max(1, Int(((1 - tokens) / perSecond).rounded(.up)))))
            }
            state.ledger.buckets[subject] = (tokens - 1, time)
            // The allowance.
            let usage = snapshot(state, subject: subject, category: category)
            if usage.usedToday >= usage.limitToday || usage.usedThisMonth >= usage.limitThisMonth {
                let resetAt = usage.resetsAt?.date ?? time.addingTimeInterval(60)
                return .reply(
                    error(
                        .quotaExceeded, id, retryAfter: max(1, Int(resetAt.timeIntervalSince(time).rounded(.up))),
                        category: category, resetAt: resetAt))
            }
            var action = FakeLedger.Action(
                id: "act_" + FakeToken.randomHex(16), subject: subject, fingerprint: fingerprint, feature: feature,
                category: category, createdAt: Self.millisecondPrecision(time))
            if let styleRequest, let cacheKey {
                // 27a: the result cache first (no job, no allowance), then the stylist.
                if let cached = state.ledger.styleCache[cacheKey], cached.at > time.addingTimeInterval(-86_400) {
                    var again = cached.result
                    again.fromCache = true
                    action.style = again
                    action.counted = false
                } else if state.limits.stylist == .fails {
                    state.ledger.jobsRun += 1
                    return .reply(
                        error(
                            .unavailable, id, message: "It didn't work this time. It wasn't counted.", retryAfter: 30))
                } else {
                    state.ledger.jobsRun += 1
                    let result = FakeStylist.answer(styleRequest)
                    action.style = result
                    action.counted = result.kind != "insufficient"
                    if result.kind != "insufficient" { state.ledger.styleCache[cacheKey] = (result, time) }
                }
            } else {
                state.ledger.jobsRun += 1
            }
            state.ledger.actions[actionKey] = action
            return .done(action, replayed: false, usage: snapshot(state, subject: subject, category: category))
        }
        switch outcome {
        case .reply(let reply):
            return reply
        case .done(let action, let replayed, let usage):
            let paidAction = APIV1.PaidAction(
                id: action.id, kind: action.feature, status: "succeeded", replayed: replayed,
                createdAt: .init(action.createdAt))
            if let style = action.style {
                return encode(200, APIV1.StyleResponse(action: paidAction, result: style, usage: usage), id)
            }
            return encode(
                200, APIV1.PaidActionResponse(action: paidAction, result: .init(placeholder: true), usage: usage), id)
        }
    }

    /// Checks an assertion like the real gateway does and returns its counter, or nil. The counter
    /// is compared with the stored one under the lock, with the rest of admission.
    private func verify(assertion: Data, keyID: String, subject: String, clientData: String) -> UInt32? {
        guard let key = state.withLock({ $0.ledger.keys[keyID] }), key.subject == subject,
            let map = MiniCBOR.decodeMap(assertion), let signatureDER = map["signature"],
            let authData = map["authenticatorData"], authData.count >= 37,
            authData.prefix(32) == Data(SHA256.hash(data: Data(FakeDeviceAttester.appID.utf8))),
            let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureDER)
        else { return nil }
        let bytes = [UInt8](authData)
        let counter = UInt32(bytes[33]) << 24 | UInt32(bytes[34]) << 16 | UInt32(bytes[35]) << 8 | UInt32(bytes[36])
        let nonce = Data(SHA256.hash(data: authData + AttestClientData.hash(clientData)))
        return key.publicKey.isValidSignature(signature, for: nonce) ? counter : nil
    }
}
