import AuthenticationServices
import UIKit

/// One Sign in with Apple request, for its authorization code (Phase 24c). The code is short-lived
/// and works once; it goes straight to the backend, which revokes the Apple link with it, and is
/// never stored. Asks for no name and no email, like sign-in (D6).
@MainActor
final class AppleReauthentication: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<String, any Error>?

    static func authorizationCode() async throws -> String {
        let request = AppleReauthentication()
        return try await request.run()
    }

    private func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let appleRequest = ASAuthorizationAppleIDProvider().createRequest()
            appleRequest.requestedScopes = []
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
        let code = credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            if let code {
                continuation?.resume(returning: code)
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
