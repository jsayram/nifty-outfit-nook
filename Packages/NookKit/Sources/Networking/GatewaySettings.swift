import Foundation

/// Which backend and sign-in the app uses, read from its Info.plist. The values come from
/// build settings in `Configs/Secrets.xcconfig`, which git ignores; `Secrets.xcconfig.example`
/// shows the keys. Neither value is a secret (both ship in the app), but they stay out of the
/// public repo until Jose sets up the services (docs/backend-switch.md).
///
/// With both set, the app signs in through Clerk and calls the Convex deployment. With either
/// missing or malformed, it runs on the fake sign-in and the in-process fake backend.
public struct GatewaySettings: Sendable, Equatable {
    public static let publishableKeyInfoKey = "NookClerkPublishableKey"
    public static let apiBaseURLInfoKey = "NookAPIBaseURL"

    public var clerkPublishableKey: String?
    public var apiBaseURL: URL?

    public init(clerkPublishableKey: String?, apiBaseURL: URL?) {
        self.clerkPublishableKey = clerkPublishableKey
        self.apiBaseURL = apiBaseURL
    }

    /// Reads the two Info.plist values, ignoring empty ones and unexpanded "$(...)" settings.
    public init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let text = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty, !text.contains("$(")
            else { return nil }
            return text
        }
        let key = value(Self.publishableKeyInfoKey)
        self.clerkPublishableKey = key.flatMap {
            $0.wholeMatch(of: /pk_(test|live)_[A-Za-z0-9+\/=_-]{10,}/) != nil ? $0 : nil
        }
        self.apiBaseURL = value(Self.apiBaseURLInfoKey).flatMap { text in
            // https only, with a host, and no query string and no user name or password in it: a
            // web address with credentials would put them in the app.
            guard let url = URL(string: text), url.scheme == "https", url.host() != nil, url.query() == nil,
                url.user() == nil, url.password() == nil
            else {
                return nil
            }
            return url
        }
    }

    /// True when the real services are configured, so the app uses Clerk and the real backend.
    public var usesRealServices: Bool {
        clerkPublishableKey != nil && apiBaseURL != nil
    }
}

/// The gateway the app runs on without a Clerk key: the fake sign-in and the in-process fake
/// backend, through the same `APIClient` and `GatewayAccountService` the real one uses.
public struct FakeGateway: Sendable {
    public let auth: FakeAuthProvider
    public let backend: FakeBackend
    public let account: GatewayAccountService
    /// 24b: paid actions, signed by a stand-in for App Attest (the simulator can't attest).
    public let attester: FakeDeviceAttester
    public let paid: GatewayPaidActionService
    /// 24d: notes to the support queue.
    public let feedback: GatewayFeedbackService
    /// 30b: picture-credit claims.
    public let credits: GatewayCreditClaimer

    public init(
        appVersion: String, tokenLifetime: TimeInterval = 60, policy: RetryPolicy = .standard,
        onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) {
        let auth = FakeAuthProvider(lifetime: tokenLifetime)
        let backend = FakeBackend()
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy, onEvent: onEvent)
        self.auth = auth
        self.backend = backend
        let attester = FakeDeviceAttester()
        self.attester = attester
        let attestation = AttestationSession(attester: attester, store: MemoryAttestKeyStore(), client: client)
        self.account = GatewayAccountService(
            auth: auth, client: client, appVersion: appVersion, attestation: attestation)
        self.paid = GatewayPaidActionService(client: client, attestation: attestation)
        self.feedback = GatewayFeedbackService(auth: auth, client: client)
        self.credits = GatewayCreditClaimer(client: client)
    }
}
