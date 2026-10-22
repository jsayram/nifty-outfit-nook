import Foundation
import Models

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
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
        /// 30c: styling purchases claimed, by original transaction ID: the account and the product.
        var entitlements: [String: (subject: String, productID: String)] = [:]
        var entitlementClaims = 0
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
                let grant = FakeCredits.Grant(
                    subject: subject, productID: productID, pictures: pictures, claimedAt: time)
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

        /// 30c: the account's purchase token, made from its ID (the real backend keeps a random one).
        static func user(_ id: String, _ createdAt: Date) -> APIV1.User {
            var hex = Array(id.dropFirst(4))
            hex[12] = "4"
            hex[16] = "8"
            let s = String(hex)
            let token = [
                s.prefix(8), s.dropFirst(8).prefix(4), s.dropFirst(12).prefix(4), s.dropFirst(16).prefix(4),
                s.dropFirst(20),
            ]
            .joined(separator: "-")
            return APIV1.User(id: id, createdAt: createdAt, appAccountToken: token)
        }

        /// Styling-access claims received, including repeats and refusals.
        public var stylingClaims: Int { state.withLock { $0.credits.entitlementClaims } }

        /// 30c: POST /v1/entitlements/claim, as the real gateway does it without Apple's signature
        /// check: the subscription or the unlock, linked to the first account that claims it; another
        /// account is forbidden. Access from the payload's dates.
        func routeEntitlement(_ request: URLRequest, body: Data?, subject: String, id: String) -> FakeReply {
            let type = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard type.lowercased().hasPrefix("application/json") else { return error(.unsupportedMediaType, id) }
            guard let body, body.count <= APIV1.maxBodyBytes,
                let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any], object.count == 1,
                let jws = object["signedTransaction"] as? String, jws.count <= 16_384,
                jws.wholeMatch(of: /[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/) != nil
            else { return error(.invalidRequest, id) }
            state.withLock { $0.credits.entitlementClaims += 1 }
            guard state.withLock({ $0.credits.available }) else {
                return error(.unavailable, id, message: "Purchases can't be checked right now.", retryAfter: 3600)
            }
            let styling = [SubscriptionProducts.monthly: "subscription", SubscriptionProducts.complimentary: "unlock"]
            guard let payload = Self.payload(of: jws), let original = payload["originalTransactionId"] as? String,
                payload["bundleId"] as? String == FakeCredits.bundleID, let productID = payload["productId"] as? String,
                let source = styling[productID]
            else { return error(.invalidRequest, id, message: "That signed transaction can't be verified.") }
            let owner = state.withLock { state -> String in
                if let earlier = state.credits.entitlements[original] { return earlier.subject }
                state.credits.entitlements[original] = (subject, productID)
                return subject
            }
            guard owner == subject else {
                return error(.forbidden, id, message: "That purchase belongs to another account.")
            }
            var access = payload["revocationDate"] == nil
            var expiresAt: APIV1.DateTime?
            if source == "subscription", let ms = payload["expiresDate"] as? Double {
                let expires = Date(timeIntervalSince1970: ms / 1000)
                access = access && expires > now()
                expiresAt = .init(Self.millisecondPrecision(expires))
            }
            return encode(
                200,
                APIV1.EntitlementClaimResponse(
                    productId: productID,
                    styling: .init(
                        access: access, source: access ? source : "none", expiresAt: access ? expiresAt : nil)),
                id)
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
#endif
