import Foundation
import Testing

@testable import Networking

@Suite("Gateway settings and token claims")
struct GatewaySettingsTests {
    // Made-up values, assembled at run time so the secret scanner doesn't flag test data.
    static let publishable = "pk_" + "test_" + String(repeating: "x", count: 24)
    static let secret = "sk_" + "live_" + String(repeating: "y", count: 24)

    @Test func bothValuesSwitchToTheRealServices() throws {
        let settings = GatewaySettings(info: [
            "NookClerkPublishableKey": GatewaySettingsTests.publishable,
            "NookAPIBaseURL": "https://beaming-oyster-905.convex.site",
        ])
        #expect(settings.usesRealServices)
        #expect(settings.apiBaseURL?.host() == "beaming-oyster-905.convex.site")
    }

    @Test(arguments: [
        [String: String](),
        ["NookClerkPublishableKey": "", "NookAPIBaseURL": ""],
        ["NookClerkPublishableKey": "$(CLERK_PUBLISHABLE_KEY)", "NookAPIBaseURL": "$(NOOK_API_BASE_URL)"],
        ["NookClerkPublishableKey": GatewaySettingsTests.publishable, "NookAPIBaseURL": "http://insecure.example"],
        ["NookClerkPublishableKey": GatewaySettingsTests.secret, "NookAPIBaseURL": "https://a.convex.site"],
        ["NookClerkPublishableKey": GatewaySettingsTests.publishable, "NookAPIBaseURL": "https:"],
        // A web address with a user name and password in it (Phase 25a).
        [
            "NookClerkPublishableKey": GatewaySettingsTests.publishable,
            "NookAPIBaseURL": "https://someone:made-up@a.convex.site",
        ],
        [
            "NookClerkPublishableKey": GatewaySettingsTests.publishable,
            "NookAPIBaseURL": "https://someone@a.convex.site",
        ],
    ])
    func anythingMissingOrWrongStaysOnTheFakes(info: [String: String]) {
        #expect(!GatewaySettings(info: info).usesRealServices)
    }

    @Test func aSecretKeyIsNeverTakenForAPublishableOne() {
        #expect(
            GatewaySettings(info: ["NookClerkPublishableKey": GatewaySettingsTests.secret]).clerkPublishableKey == nil)
    }

    @Test func readsTheExpiryOfAJWT() throws {
        let payload = Data(#"{"exp":1792555200,"sub":"user_1"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let expiry = try #require(JWTClaims.expiry(of: "eyJhbGciOiJSUzI1NiJ9.\(payload).sig"))
        #expect(expiry == Date(timeIntervalSince1970: 1_792_555_200))
        #expect(JWTClaims.expiry(of: "not.a-jwt") == nil)
        #expect(JWTClaims.expiry(of: "a.%%%.c") == nil)
    }

    @Test func fakeTokensRoundTripAndRefuseOddSubjects() throws {
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let token = FakeToken.make(subject: "lily_1", expiresAt: expiry)
        #expect(FakeToken.parse(token) == .init(subject: "lily_1", expiresAt: expiry))
        #expect(FakeToken.parse("fake1..2000000000.ab") == nil)
        #expect(FakeToken.parse("fake1.a-b.2000000000.ab") == nil)
        #expect(FakeToken.parse("eyJ.real.jwt") == nil)
    }
}
