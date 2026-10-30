import Foundation
import Testing

@testable import Networking

@Suite("Gateway settings and token claims")
struct GatewaySettingsTests {
    @Test func theBackendAddressSwitchesToTheRealServices() throws {
        let settings = GatewaySettings(info: ["NookAPIBaseURL": "https://beaming-oyster-905.convex.site"])
        #expect(settings.usesRealServices)
        #expect(settings.apiBaseURL?.host() == "beaming-oyster-905.convex.site")
    }

    @Test(arguments: [
        [String: String](),
        ["NookAPIBaseURL": ""],
        ["NookAPIBaseURL": "$(NOOK_API_BASE_URL)"],
        ["NookAPIBaseURL": "http://insecure.example"],
        ["NookAPIBaseURL": "https:"],
        ["NookAPIBaseURL": "https://a.convex.site?debug=1"],
        // A web address with a user name and password in it (Phase 25a).
        ["NookAPIBaseURL": "https://someone:made-up@a.convex.site"],
        ["NookAPIBaseURL": "https://someone@a.convex.site"],
        // BA4: the old Clerk key alone configures nothing.
        ["NookClerkPublishableKey": "pk_" + "test_" + String(repeating: "x", count: 24)],
    ])
    func anythingMissingOrWrongStaysOnTheFakes(info: [String: String]) {
        #expect(!GatewaySettings(info: info).usesRealServices)
    }

    // MARK: Release fails closed (32b, L9)

    private static let configured = GatewaySettings(info: ["NookAPIBaseURL": "https://beaming-oyster-905.convex.site"])

    @Test func aReleaseBuildWithNoSettingsHasNoFakes() {
        // `allowsFakes` is false in a Release build: the app passes it from `#if DEBUG`.
        #expect(GatewayMode.resolve(settings: GatewaySettings(info: [:]), allowsFakes: false) == .unavailable)
    }

    @Test(arguments: [
        ["NookAPIBaseURL": ""],
        ["NookAPIBaseURL": "$(NOOK_API_BASE_URL)"],
        ["NookAPIBaseURL": "http://insecure.example"],
        ["NookAPIBaseURL": "http://127.0.0.1:3211"],
    ])
    func aReleaseBuildWithMissingOrWrongSettingsNeverFallsBackToTheFakes(info: [String: String]) {
        #expect(GatewayMode.resolve(settings: GatewaySettings(info: info), allowsFakes: false) == .unavailable)
    }

    @Test func aDebugBuildWithNoSettingsKeepsTheFakes() {
        #expect(GatewayMode.resolve(settings: GatewaySettings(info: [:]), allowsFakes: true) == .fake)
    }

    @Test func configuredSettingsAreTheRealServicesInEveryBuild() {
        #expect(GatewayMode.resolve(settings: Self.configured, allowsFakes: false) == .real)
        #expect(GatewayMode.resolve(settings: Self.configured, allowsFakes: true) == .real)
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
