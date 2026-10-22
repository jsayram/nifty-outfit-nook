import Foundation

/// Which backend and sign-in the app uses, read from its Info.plist. The values come from
/// build settings in `Configs/Secrets.xcconfig`, which git ignores; `Secrets.xcconfig.example`
/// shows the keys. Neither value is a secret (both ship in the app), but they stay out of the
/// public repo until Jose sets up the services (docs/backend-switch.md).
///
/// With both set, the app signs in through Clerk and calls the Convex deployment. With either
/// missing or malformed, a Debug build runs on the fake sign-in and the in-process fake backend,
/// and a Release build runs on nothing: cloud features say they aren't available (`GatewayMode`).
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

/// Which gateway a build runs on. Decided once, from the settings and the build kind.
///
/// Release fails closed (32b, L9): with the settings missing, a Release build has no fake sign-in
/// and no fake backend to fall back to, so it reports `.unavailable` and the cloud features show a
/// calm "not available right now". `FakeGateway` doesn't exist in a Release build at all
/// (`scripts/check-release.sh` checks the binary).
public enum GatewayMode: Sendable, Equatable {
    /// Clerk and the Convex deployment.
    case real
    /// The in-process fakes. Debug builds only.
    case fake
    /// No backend: signed out, nothing cloud works, nothing is simulated.
    case unavailable

    /// - Parameter allowsFakes: true only in a Debug build (`#if DEBUG` at the call site).
    public static func resolve(settings: GatewaySettings, allowsFakes: Bool) -> GatewayMode {
        if settings.usesRealServices { return .real }
        return allowsFakes ? .fake : .unavailable
    }
}
