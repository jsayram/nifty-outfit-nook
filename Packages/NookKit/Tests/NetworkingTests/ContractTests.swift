import CryptoKit
import Foundation
import Testing

@testable import Networking

/// The Swift side of the shared contract. `Contract/` is a byte-identical copy of the backend
/// repo's `contract/` (copied by its `scripts/sync-contract.mjs`); the backend tests read the same
/// files.
@Suite("Contract v1")
struct ContractTests {
    static let root = Bundle.module.url(forResource: "Contract", withExtension: nil)!

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appending(path: path))
    }

    static func contract() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data("v1/contract.json")) as? [String: Any])
    }

    /// Two JSON documents mean the same thing.
    static func sameJSON(_ a: Data, _ b: Data) throws -> Bool {
        let left = try JSONSerialization.jsonObject(with: a) as? NSObject
        let right = try JSONSerialization.jsonObject(with: b) as? NSObject
        return left != nil && left == right
    }

    @Test func theCopyMatchesItsManifest() throws {
        // A hand edit here, instead of a sync from the backend repo, fails this test.
        let manifest = try String(decoding: Self.data("MANIFEST.sha256"), as: UTF8.self)
        let lines = manifest.split(separator: "\n")
        #expect(lines.count >= 10)
        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            let file = try Self.data(String(parts[1]))
            let digest = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
            #expect(digest == String(parts[0]), "\(parts[1]) differs from the backend's contract")
        }
    }

    @Test func versionAndLimitsMatch() throws {
        let contract = try Self.contract()
        #expect(contract["version"] as? Int == APIV1.version)
        #expect(contract["basePath"] as? String == "/v\(APIV1.version)")
        #expect((contract["limits"] as? [String: Any])?["maxBodyBytes"] as? Int == APIV1.maxBodyBytes)
    }

    @Test func endpointsMatch() throws {
        let listed = try #require(Self.contract()["endpoints"] as? [[String: Any]])
        let fromContract = listed.map { "\($0["id"]!) \($0["method"]!) \($0["path"]!) \($0["auth"]!)" }.sorted()
        let fromSwift = APIV1.endpoints.map {
            "\($0.id) \($0.method) \($0.path) \($0.requiresAuth ? "required" : "none")"
        }
        .sorted()
        #expect(fromContract == fromSwift)
    }

    @Test func errorCodesAndStatusesMatch() throws {
        let listed = try #require(Self.contract()["errors"] as? [[String: Any]])
        let fromContract = Dictionary(
            uniqueKeysWithValues: listed.map { ($0["code"] as! String, $0["status"] as! Int) })
        let fromSwift = Dictionary(uniqueKeysWithValues: APIV1.ErrorCode.allCases.map { ($0.rawValue, $0.status) })
        #expect(fromContract == fromSwift)
    }

    @Test(arguments: [
        ("v1/examples/health.response.json", "health"),
        ("v1/examples/session.request.json", "sessionRequest"),
        ("v1/examples/session.response.json", "sessionResponse"),
        ("v1/examples/me.response.json", "me"),
        ("v1/examples/error.token_expired.json", "error"),
        ("v1/examples/error.rate_limited.json", "error"),
        ("v1/examples/error.invalid_request.json", "error"),
    ])
    func goldenExamplesRoundTrip(path: String, type: String) throws {
        // Decoding then encoding gives the same JSON: the Swift types neither drop nor add a field.
        let original = try Self.data(path)
        let decoder = JSONDecoder()
        let encoder = APIV1.encoder()
        let reencoded: Data =
            switch type {
            case "health": try encoder.encode(decoder.decode(APIV1.Health.self, from: original))
            case "sessionRequest": try encoder.encode(decoder.decode(APIV1.SessionRequest.self, from: original))
            case "sessionResponse": try encoder.encode(decoder.decode(APIV1.SessionResponse.self, from: original))
            case "me": try encoder.encode(decoder.decode(APIV1.Me.self, from: original))
            default: try encoder.encode(decoder.decode(APIV1.ErrorEnvelope.self, from: original))
            }
        #expect(try Self.sameJSON(original, reencoded), "\(path)")
    }

    @Test func everyErrorExampleUsesAKnownCode() throws {
        for name in ["token_expired", "rate_limited", "invalid_request"] {
            let envelope = try JSONDecoder().decode(
                APIV1.ErrorEnvelope.self, from: Self.data("v1/examples/error.\(name).json"))
            #expect(APIV1.ErrorCode(rawValue: envelope.error.code) != nil)
        }
    }

    @Test func datesKeepMilliseconds() throws {
        let date = try #require(APIV1.parseDate("2026-10-21T03:00:00.123Z"))
        #expect(APIV1.formatDate(date) == "2026-10-21T03:00:00.123Z")
        #expect(APIV1.parseDate("2026-10-21T03:00:00Z") != nil)
        #expect(APIV1.parseDate("yesterday") == nil)
    }
}
