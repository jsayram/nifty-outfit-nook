import DesignSystem
import Models
import Observation
import SwiftUI

/// Why she's being asked to sign in: the cloud feature she just started. The sheet's title and
/// first line say which.
public enum SignInReason: String, Hashable, Sendable, CaseIterable {
    /// Style Me with the cloud stylist (and Ask stylist).
    case styling
    /// A real try-on picture.
    case tryOn
    /// Buying styling access or a picture pack: the purchase is claimed on the server.
    case stylingAccess
    /// Sending a note to the support queue.
    case support
    /// Sending a report about an AI result.
    case report
    /// Delete my account, when the session has ended.
    case deleteAccount
    /// Profile's Sign in row: nothing started, she chose to.
    case account
}

/// Asks her to sign in before a cloud feature, and answers whether to carry on (Release).
///
/// Nothing asks at launch: her closet, Quick ideas, backups and everything else on the phone
/// work signed out. Only when she starts something that needs the server does a screen call
/// `ask`. Signed in already, it answers yes at once. Signed out, the sign-in sheet opens; Sign in
/// with Apple answers yes and the action she started carries on, Not now (or closing the sheet)
/// answers no and nothing is sent.
///
/// A screen reads it from the environment (`\.signIn`). The app's root and each sheet that starts
/// cloud work install one with `.signInGate()`, because a sheet can't be presented from under
/// another sheet. Without one (previews, tests) every ask answers yes, so the screens behave as
/// they did before.
public struct SignInCheck: Sendable {
    let ask: @MainActor @Sendable (SignInReason) async -> Bool
    /// False for `notNeeded`: a screen can then go on at once, without waiting for an answer.
    public let isInstalled: Bool

    public init(ask: @escaping @MainActor @Sendable (SignInReason) async -> Bool) {
        self.ask = ask
        isInstalled = true
    }

    private init(notNeeded: Void) {
        ask = { _ in true }
        isInstalled = false
    }

    /// Asks, if she isn't signed in. True when the action may go on.
    @MainActor public func callAsFunction(_ reason: SignInReason) async -> Bool {
        await ask(reason)
    }

    /// No sheet to show: every action goes on. Previews and tests that don't test signing in.
    public static let notNeeded = SignInCheck(notNeeded: ())
}

extension EnvironmentValues {
    /// The sign-in check for this part of the app (`.signInGate()`).
    @Entry public var signIn = SignInCheck.notNeeded
}

/// The state behind the sign-in sheet: which ask is waiting, and Sign in with Apple's progress.
@MainActor
@Observable
final class SignInGate {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let reason: SignInReason
    }

    /// The sheet is open for this ask.
    var request: Request?
    private(set) var isSigningIn = false
    /// What went wrong with the last Sign in with Apple. Closing Apple's sheet isn't a problem.
    private(set) var problem: AccountProblem?
    /// Styling's Not now, kept while the app runs: Style Me opens often, and asking every time
    /// would nag. Your looks still offers Sign in beside Quick ideas.
    private(set) var declined: Set<SignInReason> = []

    @ObservationIgnored private var waiting: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var account: any AccountService = UnavailableAccountService()

    /// - Returns: true when she's signed in (already, or now), or when there's no sign-in to ask
    ///   for: a build with no backend says the feature isn't available on its own.
    func ask(_ reason: SignInReason, services: NookServices, remembersNotNow: Bool = true) async -> Bool {
        guard services.offersSignIn, !services.cloudUnavailable else { return true }
        if await services.account.isSignedIn() { return true }
        if remembersNotNow, declined.contains(reason) { return false }
        // One ask at a time. A second while the sheet is open waits for nothing and says no.
        guard waiting == nil else { return false }
        account = services.account
        problem = nil
        return await withCheckedContinuation { continuation in
            waiting = continuation
            request = Request(reason: reason)
        }
    }

    /// Sign in with Apple, from the sheet. Success closes the sheet and the action carries on.
    func signIn() async {
        guard !isSigningIn, request != nil else { return }
        isSigningIn = true
        problem = nil
        defer { isSigningIn = false }
        do {
            _ = try await account.signIn()
            finish(true)
        } catch .cancelled {
            // She closed Apple's sheet: this one stays, so she can try again or say Not now.
        } catch {
            problem = error
            if let text = CloudProblemText.message(for: error) { CloudProblemText.announce(text) }
        }
    }

    /// Not now: nothing is sent, and the screen carries on without the cloud.
    func notNow() {
        if request?.reason == .styling { declined.insert(.styling) }
        finish(false)
    }

    /// The sheet went away (swiped down, or closed by Not now or signing in).
    func dismissed() {
        finish(false)
    }

    /// Signing in from Profile or a Sign in button forgets an earlier Not now.
    func forgetNotNow() {
        declined = []
    }

    private func finish(_ signedIn: Bool) {
        request = nil
        let continuation = waiting
        waiting = nil
        continuation?.resume(returning: signedIn)
    }
}

/// Installs a sign-in check and its sheet here (`SignInCheck`).
struct SignInGateModifier: ViewModifier {
    @Environment(\.services) private var services
    @State private var gate = SignInGate()

    func body(content: Content) -> some View {
        let gate = gate
        let services = services
        content
            .environment(\.signIn, SignInCheck { reason in await gate.ask(reason, services: services) })
            .environment(
                \.signInAgain,
                SignInCheck { reason in
                    gate.forgetNotNow()
                    return await gate.ask(reason, services: services, remembersNotNow: false)
                }
            )
            .nookSheet(
                item: Binding(get: { gate.request }, set: { if $0 == nil { gate.dismissed() } }),
                title: { SignInText.title(for: $0.reason) },
                detents: [.large],
                onDismiss: { gate.dismissed() },
                content: { request in SignInSheet(gate: gate, reason: request.reason) }
            )
    }
}

extension EnvironmentValues {
    /// Asks even after an earlier Not now: a Sign in button she tapped herself.
    @Entry public var signInAgain = SignInCheck.notNeeded
}

extension View {
    /// Installs a sign-in check and its sheet for the views inside (Release). Put it at the root
    /// and on every sheet whose content starts cloud work.
    public func signInGate() -> some View {
        modifier(SignInGateModifier())
    }
}
