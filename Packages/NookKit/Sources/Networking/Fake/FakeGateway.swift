import Foundation

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
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
#endif
