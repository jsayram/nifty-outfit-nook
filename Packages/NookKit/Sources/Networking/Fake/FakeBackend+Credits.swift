import Foundation

// The fake backend's 30b half: picture credits, as the real gateway's mocked claim does them
// (convex/credits.ts in the backend repo). It reads the transaction and product from the JWS
// payload without checking Apple's signature, credits the pack's size from its own list, and
// credits each transaction ID once: the same account again gets the first grant back (replayed),
// another account is forbidden.

struct FakeCredits {
    struct Grant {
        var subject: String
        var productID: String
        var pictures: Int
        var claimedAt: Date
    }

    /// PLACEHOLDER sizes, the same as the backend's CREDIT_PACKS.
    static let packs = [
        "com.jsayram.niftyoutfitnook.pictures.small": 10, "com.jsayram.niftyoutfitnook.pictures.large": 30,
    ]
    static let bundleID = "com.jsayram.niftyoutfitnook"

    /// By transaction ID.
    var grants: [String: Grant] = [:]
    /// False answers every claim with unavailable, as the real backend does until its crediting
    /// is turned on.
    var available = true
    var claims = 0

    func balance(of subject: String) -> Int {
        grants.values.filter { $0.subject == subject }.reduce(0) { $0 + $1.pictures }
    }
}

extension FakeBackend {
    // MARK: Controls for tests and the debug screen

    /// Turns crediting on or off. Off, every claim is unavailable and nothing is credited.
    public func setCreditsAvailable(_ available: Bool) {
        state.withLock { $0.credits.available = available }
    }

    /// Picture credits an account has, by its sign-in subject.
    public func creditBalance(subject: String) -> Int {
        state.withLock { $0.credits.balance(of: subject) }
    }

    /// Transactions credited, across all accounts.
    public var creditedTransactions: Int { state.withLock { $0.credits.grants.count } }

    /// Claims received, including repeats and refusals.
    public var creditClaims: Int { state.withLock { $0.credits.claims } }

    func routeCredits(_ request: URLRequest, body: Data?, subject: String, id: String) -> FakeReply {
        let type = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard type.lowercased().hasPrefix("application/json") else { return error(.unsupportedMediaType, id) }
        guard let body, body.count <= APIV1.maxBodyBytes else { return error(.payloadTooLarge, id) }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any], object.count == 1,
            let jws = object["signedTransaction"] as? String, jws.count <= 16_384,
            jws.wholeMatch(of: /[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/) != nil
        else { return error(.invalidRequest, id) }
        state.withLock { $0.credits.claims += 1 }
        guard state.withLock({ $0.credits.available }) else {
            return error(.unavailable, id, message: "Picture packs can't be credited yet.", retryAfter: 3600)
        }
        guard let payload = Self.payload(of: jws), let transactionID = payload["transactionId"] as? String,
            transactionID.wholeMatch(of: /[0-9]{1,20}/) != nil, let productID = payload["productId"] as? String,
            payload["bundleId"] as? String == FakeCredits.bundleID, payload["type"] as? String == "Consumable",
            payload["revocationDate"] == nil, let pictures = FakeCredits.packs[productID]
        else { return error(.invalidRequest, id, message: "That isn't a picture pack for this app.") }

        let time = Self.millisecondPrecision(now())
        let answer = state.withLock { state -> (FakeCredits.Grant, replayed: Bool, balance: Int)? in
            if let earlier = state.credits.grants[transactionID] {
                guard earlier.subject == subject else { return nil }
                return (earlier, true, state.credits.balance(of: subject))
            }
            let grant = FakeCredits.Grant(subject: subject, productID: productID, pictures: pictures, claimedAt: time)
            state.credits.grants[transactionID] = grant
            return (grant, false, state.credits.balance(of: subject))
        }
        guard let answer else {
            return error(.forbidden, id, message: "That purchase can't be credited to this account.")
        }
        return encode(
            200,
            APIV1.CreditClaimResponse(
                claim: .init(
                    transactionId: transactionID, productId: answer.0.productID, pictures: answer.0.pictures,
                    replayed: answer.replayed, claimedAt: .init(answer.0.claimedAt)),
                credits: .init(pictures: answer.balance)), id)
    }

    /// The JWS payload as JSON, unverified (the real backend checks Apple's signature from 30c).
    static func payload(of jws: String) -> [String: Any]? {
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacing("-", with: "+").replacing("_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: String(base64)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
