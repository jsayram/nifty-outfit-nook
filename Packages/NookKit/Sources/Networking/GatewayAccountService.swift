import Foundation
import Models

/// `AccountService` over the v1 gateway: Sign in with Apple through the `AuthProvider`, then
/// POST /v1/session; who am I is GET /v1/me. The same code runs against the in-process fake
/// backend and the real Convex deployment; only the base URL and the `URLSession` differ.
public struct GatewayAccountService: AccountService {
    private let auth: any AuthProvider
    private let client: APIClient
    private let appVersion: String

    public init(auth: any AuthProvider, client: APIClient, appVersion: String) {
        self.auth = auth
        self.client = client
        self.appVersion = appVersion
    }

    public var providerKind: AuthProviderKind { auth.kind }

    public func isSignedIn() async -> Bool {
        await auth.isSignedIn()
    }

    public func signIn() async throws(AccountProblem) -> AccountUser {
        do {
            try await auth.signInWithApple()
        } catch {
            switch error {
            case .cancelled: throw .cancelled
            case .offline: throw .offline
            case .signedOut, .failed: throw .signedOut
            }
        }
        return try await registerSession()
    }

    public func whoAmI() async throws(AccountProblem) -> AccountUser {
        do {
            let me = try await client.send(APIV1.me, as: APIV1.Me.self)
            return AccountUser(id: me.user.id, createdAt: me.user.createdAt)
        } catch .notRegistered {
            // Signed in, but the session was never registered (for example the app closed right
            // after Apple's sheet). Registering is safe to repeat, so do it now.
            return try await registerSession()
        } catch {
            throw Self.problem(for: error)
        }
    }

    public func signOut() async {
        await auth.signOut()
    }

    private func registerSession() async throws(AccountProblem) -> AccountUser {
        do {
            let response = try await client.send(
                APIV1.createSession, body: APIV1.SessionRequest(appVersion: appVersion), as: APIV1.SessionResponse.self)
            return AccountUser(id: response.user.id, createdAt: response.user.createdAt)
        } catch {
            throw Self.problem(for: error)
        }
    }

    static func problem(for failure: APIFailure) -> AccountProblem {
        switch failure {
        case .offline: .offline
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        case .signedOut, .notRegistered: .signedOut
        case .forbidden: .forbidden
        case .rateLimited(let seconds): .rateLimited(retryAfterSeconds: seconds)
        case .unavailable(let seconds): .unavailable(retryAfterSeconds: seconds)
        case .serverError: .serverError
        case .updateRequired: .updateRequired
        case .invalidResponse: .invalidResponse
        case .rejected, .idempotencyConflict: .rejected
        // Paid-only answers; account calls never get them.
        case .attestationRequired, .attestationUnavailable: .forbidden
        case .actionInProgress(let seconds): .rateLimited(retryAfterSeconds: seconds)
        case .quotaExceeded(_, _, let seconds): .rateLimited(retryAfterSeconds: seconds)
        case .featurePaused(_, let seconds): .unavailable(retryAfterSeconds: seconds)
        }
    }
}
