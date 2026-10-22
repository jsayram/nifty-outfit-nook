import Foundation

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    /// The fake sign-in's tokens: "fake1.<subject>.<expiry in Unix seconds>.<nonce>". Shaped like
    /// what the real backend gets (an opaque bearer string with an expiry), but not a JWT, so a fake
    /// token can never be mistaken for a real one by Convex.
    enum FakeToken {
        static let prefix = "fake1"

        static func make(subject: String, expiresAt: Date) -> String {
            "\(prefix).\(subject).\(Int(expiresAt.timeIntervalSince1970)).\(randomHex(8))"
        }

        struct Parsed: Equatable {
            var subject: String
            var expiresAt: Date
        }

        static func parse(_ token: String) -> Parsed? {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == prefix, let seconds = Int(parts[2]),
                parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }), !parts[1].isEmpty
            else { return nil }
            return Parsed(subject: String(parts[1]), expiresAt: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }

        static func randomHex(_ bytes: Int) -> String {
            var generator = SystemRandomNumberGenerator()
            return (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }
                .joined()
        }
    }
#endif
