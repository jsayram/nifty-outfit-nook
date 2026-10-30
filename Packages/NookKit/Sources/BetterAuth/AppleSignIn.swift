import AuthenticationServices
import CryptoKit
import Foundation
import Models
import UIKit

/// Where Apple's answers come from: the real Sign in with Apple sheet in the app, or a stand-in
/// in Debug builds and tests.
public protocol AppleIdentitySource: Sendable {
    /// Runs Sign in with Apple with no scopes and the SHA-256 of `rawNonce` as the request's
    /// nonce, and returns Apple's identity token.
    func identityToken(rawNonce: String) async throws(AuthError) -> String
    /// Phase 24c: Sign in with Apple once more, for its one-time authorization code, which the
    /// backend uses to revoke the app's Apple link. Never stored.
    func authorizationCode() async throws(AuthError) -> String
}

/// The nonce for one sign-in: 32 random bytes as hex, kept by the app and sent to the backend,
/// and its SHA-256 (lowercase hex), which goes to Apple and comes back inside the identity token.
/// The backend checks that one is the other's hash, so a token lifted from another sign-in can't
/// be replayed.
public enum SignInNonce {
    public static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }

    public static func sha256(_ rawNonce: String) -> String {
        SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The real Sign in with Apple sheet. Asks for no name and no email (D6), so the sheet is one
/// step and the backend never gets either.
public struct AppleIDSignIn: AppleIdentitySource {
    public init() {}

    public func identityToken(rawNonce: String) async throws(AuthError) -> String {
        let credential = try await AppleSignInRequest.run(nonce: SignInNonce.sha256(rawNonce))
        guard let token = credential.identityToken else { throw .failed }
        return token
    }

    public func authorizationCode() async throws(AuthError) -> String {
        let credential = try await AppleSignInRequest.run(nonce: nil)
        guard let code = credential.authorizationCode else { throw .failed }
        return code
    }
}

/// One Sign in with Apple request (Phase 24c, BA4). Its identity token and authorization code
/// are short-lived; neither is stored here.
@MainActor
final class AppleSignInRequest: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    struct Credential: Sendable {
        var identityToken: String?
        var authorizationCode: String?
    }

    private var continuation: CheckedContinuation<Credential, any Error>?

    static func run(nonce: String?) async throws(AuthError) -> Credential {
        let request = AppleSignInRequest()
        do {
            return try await request.start(nonce: nonce)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw .cancelled
        } catch {
            throw .failed
        }
    }

    private func start(nonce: String?) async throws -> Credential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let appleRequest = ASAuthorizationAppleIDProvider().createRequest()
            appleRequest.requestedScopes = []
            appleRequest.nonce = nonce
            let controller = ASAuthorizationController(authorizationRequests: [appleRequest])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let answer = Credential(
            identityToken: credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) },
            authorizationCode: credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) })
        MainActor.assumeIsolated {
            if credential != nil {
                continuation?.resume(returning: answer)
            } else {
                continuation?.resume(throwing: ASAuthorizationError(.failed))
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            // Apple's sheet only runs from a screen she's looking at, so there is always a scene.
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                preconditionFailure("Sign in with Apple asked for a window with no scene connected")
            }
            return scene.keyWindow ?? scene.windows.first ?? ASPresentationAnchor(windowScene: scene)
        }
    }
}
