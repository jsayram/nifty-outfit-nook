import AuthenticationServices
import DesignSystem
import Models
import SwiftUI

/// The sign-in sheet's words (Release). Short, and it says why before it asks.
nonisolated enum SignInText {
    static func title(for reason: SignInReason) -> String {
        switch reason {
        case .styling:
            String(localized: "Sign in for cloud styling", bundle: .module, comment: "Sign-in sheet title: Style Me")
        case .tryOn:
            String(localized: "Sign in for try-on pictures", bundle: .module, comment: "Sign-in sheet title: try-on")
        case .stylingAccess:
            String(
                localized: "Sign in to get styling access", bundle: .module,
                comment: "Sign-in sheet title: buying styling access or a picture pack")
        case .support:
            String(localized: "Sign in to send this to us", bundle: .module, comment: "Sign-in sheet title: support")
        case .report:
            String(
                localized: "Sign in to send your report", bundle: .module,
                comment: "Sign-in sheet title: reporting an AI result")
        case .deleteAccount:
            String(
                localized: "Sign in to delete your account", bundle: .module,
                comment: "Sign-in sheet title: Delete my account after the session ended")
        case .account:
            String(localized: "Sign in with Apple", bundle: .module, comment: "Sign-in sheet title: from Profile")
        }
    }

    static func why(for reason: SignInReason) -> String {
        switch reason {
        case .styling:
            String(
                localized:
                    "The stylist works on our server. Signing in keeps your requests and your allowance yours, and no one else’s.",
                bundle: .module, comment: "Sign-in sheet: why, for Style Me")
        case .tryOn:
            String(
                localized:
                    "Try-on pictures are made on our server. Signing in keeps your requests and your allowance yours, and no one else’s.",
                bundle: .module, comment: "Sign-in sheet: why, for try-on")
        case .stylingAccess:
            String(
                localized: "Signing in links what you buy to your account, so our server knows it’s yours.",
                bundle: .module, comment: "Sign-in sheet: why, for buying")
        case .support:
            String(
                localized: "Signing in lets your note reach us directly, with a screenshot if you add one.",
                bundle: .module, comment: "Sign-in sheet: why, for support")
        case .report:
            String(
                localized: "Signing in lets your report reach us directly, so we can look into it.",
                bundle: .module, comment: "Sign-in sheet: why, for a report")
        case .deleteAccount:
            String(
                localized: "You were signed out. Sign in again so we can delete the account that’s yours.",
                bundle: .module, comment: "Sign-in sheet: why, for Delete my account")
        case .account:
            String(
                localized: "Signing in lets you use cloud styling, try-on pictures and styling access.",
                bundle: .module, comment: "Sign-in sheet: why, from Profile")
        }
    }

    static var stillWorks: String {
        String(
            localized: "Your closet, Quick ideas and backups work without signing in, and stay on this iPhone.",
            bundle: .module, comment: "Sign-in sheet: what works signed out")
    }

    static var whatWeKeep: String {
        String(
            localized: "Apple confirms it’s you. The app keeps only a random account number, not your name.",
            bundle: .module, comment: "Sign-in sheet: what signing in shares")
    }

    /// F1 (29 October 2026, PRD 24.2): online features are for adults. She confirms it on the sheet
    /// before Sign in with Apple works, every time the sheet opens. Nothing about it is kept.
    static var adult: String {
        String(localized: "I’m 18 or older", bundle: .module, comment: "Sign-in sheet: age confirmation switch")
    }

    static var adultDetail: String {
        String(
            localized: "Online features are for adults. Sign in with Apple works once this is on.", bundle: .module,
            comment: "Sign-in sheet: under the age confirmation switch")
    }

    static var notNow: String {
        String(localized: "Not now", bundle: .module, comment: "Sign-in sheet: decline")
    }

    static var privacy: String {
        String(localized: "Privacy policy", bundle: .module, comment: "Sign-in sheet: link to the privacy policy")
    }

    static var signingIn: String {
        String(localized: "Signing in…", bundle: .module, comment: "Sign-in sheet: while Sign in with Apple runs")
    }

    /// Profile's row (Release).
    static var signedIn: String {
        String(localized: "Signed in with Apple", bundle: .module, comment: "Profile: account row, signed in")
    }

    static var signIn: String {
        String(localized: "Sign in", bundle: .module, comment: "Profile: account row, signed out")
    }

    static var signOut: String {
        String(localized: "Sign out", bundle: .module, comment: "Profile: account row action")
    }

    static var signedInDetail: String {
        String(
            localized: "Cloud styling, try-on pictures and support use this account.", bundle: .module,
            comment: "Profile: under Signed in with Apple")
    }

    static var signedOutDetail: String {
        String(
            localized: "Only needed for cloud styling, try-on pictures and styling access.", bundle: .module,
            comment: "Profile: under Sign in, signed out")
    }

    static var signedOutNote: String {
        String(
            localized: "Signed out. Your closet stays on this iPhone.", bundle: .module,
            comment: "Profile: shown after Sign out, and read by VoiceOver")
    }

    static var unavailableDetail: String {
        String(
            localized: "Signing in isn’t available right now. Your closet still works on this iPhone.",
            bundle: .module, comment: "Profile: account row in a build with no backend")
    }

    static var accountHeader: String {
        String(localized: "Account", bundle: .module, comment: "Profile: section header for signing in")
    }
}

/// The sheet: why, Sign in with Apple (Apple's own button), Not now and the privacy policy.
struct SignInSheet: View {
    let gate: SignInGate
    let reason: SignInReason

    @State private var showsPrivacy = false
    @State private var isAdult = false

    var body: some View {
        ScrollView {
            SignInSheetContent(
                reason: reason, isSigningIn: gate.isSigningIn, problem: gate.problem, isAdult: isAdult,
                setAdult: { isAdult = $0 }, signIn: { Task { await gate.signIn() } }, notNow: gate.notNow,
                privacy: { showsPrivacy = true })
        }
        .fullScreenCover(isPresented: $showsPrivacy) {
            SafariView(url: WebsiteLink.privacyPolicy.url)
                .ignoresSafeArea()
        }
        .interactiveDismissDisabled(gate.isSigningIn)
    }
}

/// The sheet's content, apart from its scroll view, so a still image can draw it.
struct SignInSheetContent: View {
    let reason: SignInReason
    var isSigningIn = false
    var problem: AccountProblem?
    var isAdult = false
    var setAdult: @MainActor @Sendable (Bool) -> Void = { _ in }
    var signIn: () -> Void = {}
    var notNow: () -> Void = {}
    var privacy: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            line(SignInText.why(for: reason), systemImage: "icloud")
            line(SignInText.stillWorks, systemImage: "iphone")
            line(SignInText.whatWeKeep, systemImage: "lock")
            if let problem, let text = CloudProblemText.message(for: problem) {
                NookBanner(text, systemImage: "exclamationmark.circle")
                    .accessibilityIdentifier("signIn.problem")
            }
            SettingsGroup {
                SettingsSwitchRow(
                    title: SignInText.adult, detail: SignInText.adultDetail,
                    systemImage: "person.badge.shield.checkmark", isOn: isAdult, identifier: "signIn.adult",
                    set: setAdult)
            }
            VStack(spacing: NookSpacing.small) {
                AppleSignInButton(isSigningIn: isSigningIn, isEnabled: isAdult, action: signIn)
                NookButton(SignInText.notNow, kind: .soft, fillsWidth: true, action: notNow)
                    .disabled(isSigningIn)
                    .accessibilityIdentifier("signIn.notNow")
            }
            NookButton(SignInText.privacy, systemImage: "hand.raised", kind: .text, size: .small, action: privacy)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("signIn.privacy")
        }
        .padding(NookSpacing.medium)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("signIn.sheet")
    }

    private func line(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(.nook.accent)
                .accessibilityHidden(true)
            Text(text)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Apple's own Sign in with Apple button (`ASAuthorizationAppleIDButton`), black in light mode and
/// white in dark mode as Apple's guidelines ask. It only starts the app's sign-in: the
/// `AuthProvider` runs the request (Better Auth, against the fake backend in a Debug build). It keeps Apple's
/// label and look, at least 50 points tall; VoiceOver reads Apple's own label. A still image
/// (snapshot tests) draws a SwiftUI copy, since `ImageRenderer` can't draw UIKit views.
struct AppleSignInButton: View {
    var isSigningIn = false
    /// F1: off until she confirms she's 18 or older. Dimmed, and VoiceOver says it's dimmed.
    var isEnabled = true
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.closetIsStillImage) private var isStill

    static let height: CGFloat = 50
    static let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            if isStill {
                stillCopy
            } else {
                AppleIDButton(style: colorScheme == .dark ? .white : .black, action: action)
                    .id(colorScheme)
                    .accessibilityIdentifier("signIn.apple")
            }
            if isSigningIn {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel(Text(SignInText.signingIn))
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
        .allowsHitTesting(!isSigningIn && isEnabled)
    }

    private var stillCopy: some View {
        let dark = colorScheme == .dark
        return RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(dark ? Color.white : Color.black)
            .overlay {
                Label {
                    Text(verbatim: "Sign in with Apple")
                } icon: {
                    Image(systemName: "apple.logo")
                }
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(dark ? Color.black : Color.white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Sign in with Apple"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("signIn.apple")
    }
}

private struct AppleIDButton: UIViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: style)
        button.cornerRadius = AppleSignInButton.cornerRadius
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.accessibilityIdentifier = "signIn.apple"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}
