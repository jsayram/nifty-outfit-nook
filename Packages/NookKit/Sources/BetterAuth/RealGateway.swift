import Foundation
import Models
import Networking

/// The real gateway: Better Auth for sign-in and the Convex deployment's HTTP actions as the
/// backend, both at the one address in `GatewaySettings`.
public enum RealGateway {
    /// The account and the paid actions (24b, signed with Apple's App Attest) on the real backend.
    public struct Services: Sendable {
        public let account: GatewayAccountService
        public let paid: GatewayPaidActionService
        /// 24d: notes to the support queue.
        public let feedback: GatewayFeedbackService
        /// 30b: picture-credit claims.
        public let credits: GatewayCreditClaimer
        /// F1c: opt-in analytics, with no token.
        public let analytics: GatewayAnalyticsEndpoint
    }

    @MainActor
    public static func make(
        settings: GatewaySettings, appVersion: String, onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) -> Services? {
        guard settings.usesRealServices, let baseURL = settings.apiBaseURL else { return nil }
        return make(
            baseURL: baseURL, apple: AppleIDSignIn(), store: KeychainSessionStore(), appVersion: appVersion,
            onEvent: onEvent)
    }

    /// The same services for any deployment and any Apple stand-in. The app uses it directly only
    /// in Debug builds, for a local Convex backend with the fake Apple issuer.
    @MainActor
    public static func make(
        baseURL: URL, apple: any AppleIdentitySource, store: any SessionStore, appVersion: String,
        onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) -> Services {
        let session = APIClient.makeSession()
        let auth = BetterAuthProvider(
            baseURL: baseURL, session: session, store: store, apple: apple, onEvent: onEvent)
        let client = APIClient(baseURL: baseURL, session: session, auth: auth, onEvent: onEvent)
        let attestation = AttestationSession(
            attester: AppAttestDeviceAttester(), store: KeychainAttestKeyStore(), client: client)
        return Services(
            account: GatewayAccountService(
                auth: auth, client: client, appVersion: appVersion, attestation: attestation),
            paid: GatewayPaidActionService(client: client, attestation: attestation),
            feedback: GatewayFeedbackService(auth: auth, client: client),
            credits: GatewayCreditClaimer(client: client),
            analytics: GatewayAnalyticsEndpoint(client: client))
    }
}
