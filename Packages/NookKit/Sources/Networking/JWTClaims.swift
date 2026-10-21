import Foundation

/// Reads a JWT's `exp` claim, only to know when to fetch a new token. The token is never trusted
/// here: the backend verifies its signature, issuer, audience and expiry.
public enum JWTClaims {
    public static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = object["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
