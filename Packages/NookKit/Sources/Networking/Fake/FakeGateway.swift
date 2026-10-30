import Foundation
import Models

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    /// The gateway a Debug build runs on without the backend settings: the in-process fake
    /// backend, through the same `APIClient` and `GatewayAccountService` the real one uses. The app
    /// signs in with the real sign-in client against the fake's sign-in routes (`makeAuth`).
    public struct FakeGateway: Sendable {
        public let auth: any AuthProvider
        public let backend: FakeBackend
        public let account: GatewayAccountService
        /// 24b: paid actions, signed by a stand-in for App Attest (the simulator can't attest).
        public let attester: FakeDeviceAttester
        public let paid: GatewayPaidActionService
        /// 24d: notes to the support queue.
        public let feedback: GatewayFeedbackService
        /// 30b: picture-credit claims.
        public let credits: GatewayCreditClaimer

        /// - Parameter makeAuth: the sign-in, given the fake backend and the session that reaches
        ///   it. Left out, a `FakeAuthProvider` that skips the sign-in routes.
        public init(
            appVersion: String, tokenLifetime: TimeInterval = 60, policy: RetryPolicy = .standard,
            onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in },
            makeAuth: ((FakeBackend, URLSession) -> any AuthProvider)? = nil
        ) {
            let backend = FakeBackend()
            let session = APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self])
            let auth = makeAuth?(backend, session) ?? FakeAuthProvider(lifetime: tokenLifetime)
            let client = APIClient(
                baseURL: backend.baseURL, session: session, auth: auth, policy: policy, onEvent: onEvent)
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
