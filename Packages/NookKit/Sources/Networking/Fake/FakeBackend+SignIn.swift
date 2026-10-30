import CryptoKit
import Foundation

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    // BA4 in the fake backend: the contract's four sign-in routes under /api/auth, with the same
    // checks, answers and refusals as Better Auth behind the real gateway (backend BA2). It keeps
    // users, Apple links and sessions in memory; a relaunch forgets them.

    /// The fake's stand-in for Apple's identity tokens: "fakeapple.<subject>.<nonce hash>-<expiry>".
    /// Shaped like a JWT for the contract's pattern (three dot-separated parts), but not one, so
    /// it can never pass a real Apple key check.
    public enum FakeAppleToken {
        static let prefix = "fakeapple"

        /// A token for the pretend Apple user `subject`, carrying the SHA-256 of `rawNonce` the way
        /// Apple's carries the nonce the app gave it.
        public static func make(subject: String, rawNonce: String, expiresAt: Date) -> String {
            "\(prefix).\(subject).\(sha256Hex(rawNonce))-\(Int(expiresAt.timeIntervalSince1970))"
        }

        public static func sha256Hex(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        struct Parsed: Equatable {
            var subject: String
            var nonceHash: String
            var expiresAt: Date
        }

        static func parse(_ token: String) -> Parsed? {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == prefix, !parts[1].isEmpty,
                parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                let match = parts[2].wholeMatch(of: /([0-9a-f]{64})-([0-9]{1,12})/), let seconds = Int(match.2)
            else { return nil }
            return Parsed(
                subject: String(parts[1]), nonceHash: String(match.1),
                expiresAt: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
    }

    struct FakeSignIn {
        /// Better Auth's user for each pretend Apple user (its Apple account row).
        var users: [String: String] = [:]
        /// Session token → user.
        var sessions: [String: String] = [:]
        /// How long a Convex token lasts: the backend's 5 minutes.
        var convexTokenLifetime: TimeInterval = 300

        mutating func endSessions(of user: String) {
            sessions = sessions.filter { $0.value != user }
        }
    }

    extension FakeBackend {
        // MARK: Controls for tests

        /// How many sessions the fake holds (signed in and not signed out).
        public var sessionCount: Int { state.withLock { $0.signIn.sessions.count } }

        /// Ends every session, as if each had passed its 7 days.
        public func expireAllSessions() {
            state.withLock { $0.signIn.sessions.removeAll() }
        }

        /// Sets how long the fake's Convex tokens last.
        public func setConvexTokenLifetime(_ seconds: TimeInterval) {
            state.withLock { $0.signIn.convexTokenLifetime = seconds }
        }

        // MARK: Answering

        static func isSignInPath(_ path: String) -> Bool {
            path == APIV1.SignIn.basePath || path.hasPrefix(APIV1.SignIn.basePath + "/")
        }

        func routeSignIn(_ request: URLRequest, body: Data?, id: String) -> FakeReply {
            let path = request.url?.path() ?? ""
            // Better Auth's own routes beyond these four are switched off: not_found, whatever the
            // method (backend BA2).
            guard let route = APIV1.SignIn.routes.first(where: { $0.path == path && $0.method == request.httpMethod }),
                route != APIV1.SignIn.convexJwks
            else { return error(.notFound, id) }

            if route == APIV1.SignIn.signInApple { return routeAppleSignIn(request, body: body, id: id) }

            guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer "),
                case let session = String(header.dropFirst("Bearer ".count)),
                let user = state.withLock({ $0.signIn.sessions[session] }), !isDeletedSubject(user)
            else { return error(.unauthenticated, id) }

            if route == APIV1.SignIn.signOut {
                _ = state.withLock { $0.signIn.sessions.removeValue(forKey: session) }
                return encode(200, APIV1.SignIn.SignOutResponse(success: true), id)
            }
            let lifetime = state.withLock { $0.signIn.convexTokenLifetime }
            // The fake's Convex token is FakeToken's, which the fake /v1 checks. The real one is a
            // JWT signed by the deployment; the client treats both as opaque.
            let token = FakeToken.make(subject: user, expiresAt: now().addingTimeInterval(lifetime))
            return encode(200, APIV1.SignIn.ConvexTokenResponse(token: token), id)
        }

        private func routeAppleSignIn(_ request: URLRequest, body: Data?, id: String) -> FakeReply {
            let type = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard type.lowercased().hasPrefix("application/json") else { return error(.unsupportedMediaType, id) }
            guard let body, body.count <= APIV1.SignIn.signInApple.maxBodyBytes ?? 0 else {
                return error(.payloadTooLarge, id)
            }
            guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                Set(object.keys) == ["provider", "idToken"], object["provider"] as? String == "apple",
                let idToken = object["idToken"] as? [String: Any], Set(idToken.keys) == ["token", "nonce"],
                let token = idToken["token"] as? String, token.count <= 4_096,
                token.wholeMatch(of: /[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/) != nil,
                let nonce = idToken["nonce"] as? String, nonce.wholeMatch(of: /[A-Za-z0-9._~-]{16,128}/) != nil
            else { return error(.invalidRequest, id) }
            // Apple's key check, the audience and the nonce: the token must carry this nonce's hash.
            guard let apple = FakeAppleToken.parse(token), apple.expiresAt > now(),
                apple.nonceHash == FakeAppleToken.sha256Hex(nonce)
            else { return error(.unauthenticated, id) }

            let session = "fakesession_" + FakeToken.randomHex(24)
            let user = state.withLock { state -> String in
                // A deleted account's Apple link is gone, so the same Apple user gets a new user.
                let user: String
                if let existing = state.signIn.users[apple.subject],
                    !state.deletions.deletedSubjects.contains(existing)
                {
                    user = existing
                } else {
                    user = "fakeuser_" + FakeToken.randomHex(12)
                    state.signIn.users[apple.subject] = user
                }
                state.signIn.sessions[session] = user
                return user
            }
            let answer = APIV1.SignIn.AppleSignInResponse(
                redirect: false, token: session, user: .init(id: user))
            guard case .respond(let status, var headers, let data, let delay) = encode(200, answer, id) else {
                return error(.internal, id)
            }
            headers[APIV1.SignIn.sessionHeader] = session
            return .respond(status: status, headers: headers, body: data, delay: delay)
        }
    }
#endif
