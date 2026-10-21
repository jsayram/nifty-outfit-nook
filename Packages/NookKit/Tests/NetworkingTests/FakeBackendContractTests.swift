import Foundation
import Testing

@testable import Networking

/// The fake backend makes the same checks as the real gateway, so the app can't come to depend on
/// something the real one would refuse.
@Suite("Fake backend follows the contract")
struct FakeBackendContractTests {
    let backend = FakeBackend()
    let session = APIClient.makeSession(protocolClasses: [FakeBackendURLProtocol.self])

    func send(
        _ method: String, _ path: String, token: String? = nil, contentType: String? = "application/json",
        body: Data? = nil
    ) async throws -> (status: Int, body: Data, headers: [AnyHashable: Any]) {
        var request = URLRequest(url: backend.baseURL.appending(path: path))
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let contentType, body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        return (http.statusCode, data, http.allHeaderFields)
    }

    func token(_ subject: String = "lily", expiresIn: TimeInterval = 60) -> String {
        FakeToken.make(subject: subject, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    func errorCode(_ data: Data) throws -> String {
        try JSONDecoder().decode(APIV1.ErrorEnvelope.self, from: data).error.code
    }

    @Test(arguments: [
        "session.request.bad_platform.json", "session.request.missing_field.json",
        "session.request.unknown_field.json", "session.request.wrong_type.json",
    ])
    func rejectsTheContractsInvalidExamples(file: String) async throws {
        let body = try ContractTests.data("v1/examples/invalid/\(file)")
        let reply = try await send("POST", "/v1/session", token: token(), body: body)
        #expect(reply.status == 400)
        #expect(try errorCode(reply.body) == "invalid_request")
        #expect(backend.accountCount == 0)
    }

    @Test func acceptsTheGoldenRequestAndAnswersWithTheContractsShapes() async throws {
        let body = try ContractTests.data("v1/examples/session.request.json")
        let created = try await send("POST", "/v1/session", token: token(), body: body)
        #expect(created.status == 200)
        let session = try JSONDecoder().decode(APIV1.SessionResponse.self, from: created.body)
        #expect(session.newAccount)
        #expect(session.user.id.wholeMatch(of: /usr_[0-9a-f]{32}/) != nil)
        let me = try await send("GET", "/v1/me", token: token())
        #expect(try JSONDecoder().decode(APIV1.Me.self, from: me.body).user == session.user)
    }

    @Test func checksTokensBeforeBodies() async throws {
        let noToken = try await send("POST", "/v1/session", body: Data("{oops".utf8))
        #expect(noToken.status == 401)
        #expect(try errorCode(noToken.body) == "unauthenticated")
        let expired = try await send("GET", "/v1/me", token: token(expiresIn: -5))
        #expect(try errorCode(expired.body) == "token_expired")
        let garbage = try await send("GET", "/v1/me", token: "not-a-token")
        #expect(try errorCode(garbage.body) == "unauthenticated")
    }

    @Test func rejectsWrongContentTypeAndOversizedBodies() async throws {
        let body = try ContractTests.data("v1/examples/session.request.json")
        let text = try await send("POST", "/v1/session", token: token(), contentType: "text/plain", body: body)
        #expect(try errorCode(text.body) == "unsupported_media_type")
        let big =
            Data(#"{"platform":"ios","appVersion":"0.1.0","pad":""#.utf8) + Data(repeating: 0x61, count: 70_000)
            + Data(#""}"#.utf8)
        let large = try await send("POST", "/v1/session", token: token(), body: big)
        #expect(try errorCode(large.body) == "payload_too_large")
    }

    @Test func unknownPathsMethodsAndRetiredVersions() async throws {
        #expect(try errorCode(await send("GET", "/v1/nope").body) == "not_found")
        #expect(try errorCode(await send("GET", "/v0/me").body) == "api_version_retired")
        let wrong = try await send("DELETE", "/v1/me", token: token())
        #expect(wrong.status == 405)
        #expect(wrong.headers["Allow"] as? String == "GET")
    }

    @Test func everyResponseCarriesARequestIDAndNoStore() async throws {
        let reply = try await send("GET", "/v1/health")
        #expect((reply.headers["X-Request-Id"] as? String)?.hasPrefix("req_") == true)
        #expect(reply.headers["Cache-Control"] as? String == "no-store")
        #expect(try JSONDecoder().decode(APIV1.Health.self, from: reply.body).apiVersion == 1)
    }
}
