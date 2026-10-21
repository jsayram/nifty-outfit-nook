import AuthenticationServices
import ClerkKit
import Foundation
import Models
import Networking

/// Sign in with Apple through Clerk (decision D2), behind the same `AuthProvider` the fake uses.
/// The app creates it only when it has a Clerk publishable key (`GatewaySettings`).
///
/// - Asks Apple for no name and no email (D6). If the Clerk instance insists on an email, its
///   dashboard has to allow Apple's private relay address instead (docs/backend-switch.md).
/// - Tokens come from the JWT template named "convex", whose `aud` is "convex"; the backend's
///   auth config accepts nothing else.
/// - Clerk's telemetry is off. Its session lives in the Keychain (see decision 0005 for the
///   accessibility class it uses).
public final class ClerkAuthProvider: AuthProvider {
    public let kind = AuthProviderKind.clerk
    public static let jwtTemplate = "convex"

    private init() {}

    /// Configures Clerk once, at launch, and returns the provider.
    @MainActor
    public static func configure(publishableKey: String) -> ClerkAuthProvider {
        Clerk.configure(publishableKey: publishableKey, options: .init(telemetryEnabled: false))
        return ClerkAuthProvider()
    }

    public func isSignedIn() async -> Bool {
        await Self.hasSession()
    }

    public func signInWithApple() async throws(AuthError) {
        do {
            try await Self.appleSignIn()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw .cancelled
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .networkConnectionLost ? .offline : .failed
        } catch {
            throw .failed
        }
    }

    public func signOut() async {
        try? await Self.clerkSignOut()
    }

    public func token(forceRefresh: Bool) async throws(AuthError) -> AuthToken {
        let jwt: String?
        do {
            jwt = try await Self.fetchToken(forceRefresh: forceRefresh)
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .networkConnectionLost ? .offline : .failed
        } catch {
            throw .failed
        }
        guard let jwt else { throw .signedOut }
        // Clerk's session tokens last about a minute; if exp can't be read, treat it as short-lived.
        let expiresAt = JWTClaims.expiry(of: jwt) ?? Date().addingTimeInterval(30)
        return AuthToken(value: jwt, expiresAt: expiresAt)
    }

    // Clerk is main-actor isolated. These hop there and hand back only Sendable values.

    @MainActor private static func hasSession() -> Bool {
        Clerk.shared.session != nil
    }

    @MainActor private static func appleSignIn() async throws {
        try await Clerk.shared.auth.signInWithApple(requestedScopes: [])
    }

    @MainActor private static func clerkSignOut() async throws {
        try await Clerk.shared.auth.signOut()
    }

    @MainActor private static func fetchToken(forceRefresh: Bool) async throws -> String? {
        try await Clerk.shared.auth.getToken(.init(template: jwtTemplate, skipCache: forceRefresh))
    }
}

/// The real gateway: Clerk for sign-in and the Convex deployment's HTTP actions as the backend.
public enum RealGateway {
    @MainActor
    public static func make(
        settings: GatewaySettings, appVersion: String, onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) -> (any AccountService)? {
        guard settings.usesRealServices, let key = settings.clerkPublishableKey, let baseURL = settings.apiBaseURL
        else { return nil }
        let auth = ClerkAuthProvider.configure(publishableKey: key)
        let client = APIClient(baseURL: baseURL, session: APIClient.makeSession(), auth: auth, onEvent: onEvent)
        return GatewayAccountService(auth: auth, client: client, appVersion: appVersion)
    }
}
