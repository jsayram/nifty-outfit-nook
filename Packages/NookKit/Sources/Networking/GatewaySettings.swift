import Foundation

/// Which backend the app uses, read from its Info.plist. The value comes from a build setting in
/// `Configs/Secrets.xcconfig`, which git ignores; `Secrets.xcconfig.example` shows the key. It
/// isn't a secret (it ships in the app), but it stays out of the public repo until Jose sets up
/// the deployment (docs/backend-switch.md).
///
/// With it set, the app signs in through Better Auth and calls the Convex deployment, both at the
/// same `.convex.site` address (/api/auth and /v1). Missing or malformed, a Debug build runs on
/// the in-process fake backend, and a Release build runs on nothing: cloud features say they
/// aren't available (`GatewayMode`).
public struct GatewaySettings: Sendable, Equatable {
    public static let apiBaseURLInfoKey = "NookAPIBaseURL"

    public var apiBaseURL: URL?

    public init(apiBaseURL: URL?) {
        self.apiBaseURL = apiBaseURL
    }

    /// Reads the Info.plist value, ignoring an empty one and an unexpanded "$(...)" setting.
    public init(info: [String: Any]) {
        guard let text = (info[Self.apiBaseURLInfoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty, !text.contains("$("), let url = URL(string: text),
            // https only, with a host, and no query string and no user name or password in it: a
            // web address with credentials would put them in the app.
            url.scheme == "https", url.host() != nil, url.query() == nil, url.user() == nil, url.password() == nil
        else {
            self.apiBaseURL = nil
            return
        }
        self.apiBaseURL = url
    }

    /// True when the real services are configured, so the app uses Better Auth and the real backend.
    public var usesRealServices: Bool {
        apiBaseURL != nil
    }
}

/// Which gateway a build runs on. Decided once, from the settings and the build kind.
///
/// Release fails closed (32b, L9): with the settings missing, a Release build has no fake sign-in
/// and no fake backend to fall back to, so it reports `.unavailable` and the cloud features show a
/// calm "not available right now". `FakeGateway` doesn't exist in a Release build at all
/// (`scripts/check-release.sh` checks the binary).
public enum GatewayMode: Sendable, Equatable {
    /// Better Auth and the Convex deployment.
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
