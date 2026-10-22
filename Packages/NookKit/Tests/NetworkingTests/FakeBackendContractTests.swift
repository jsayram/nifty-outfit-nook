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

    /// 24c: the deletion examples the contract says are invalid are refused, and nothing is deleted.
    @Test(arguments: [
        ("deletion.request.no_confirm.json", "/v1/account/deletion"),
        ("deletion.request.wrong_confirm.json", "/v1/account/deletion"),
        ("deletion.request.user_id.json", "/v1/account/deletion"),
        ("deletion-status.request.bad_id.json", "/v1/account/deletion/status"),
    ])
    func rejectsTheContractsInvalidDeletionExamples(file: String, path: String) async throws {
        _ = try await send(
            "POST", "/v1/session", token: token(), body: ContractTests.data("v1/examples/session.request.json"))
        let body = try ContractTests.data("v1/examples/invalid/\(file)")
        let reply = try await send("POST", path, token: token(), body: body)
        #expect(reply.status == 400)
        #expect(try errorCode(reply.body) == "invalid_request")
        #expect(backend.accountCount == 1)
    }

    /// 24d: the feedback examples the contract says are invalid are refused, and nothing is kept.
    @Test(arguments: [
        "feedback.request.no_message.json", "feedback.request.blank_message.json",
        "feedback.request.long_message.json", "feedback.request.bad_kind.json", "feedback.request.user_id.json",
        "feedback.request.bad_reply_address.json", "feedback.request.bad_attachment_type.json",
        "feedback.request.extra_diagnostics_field.json", "feedback.request.closet_names.json",
    ])
    func rejectsTheContractsInvalidFeedbackExamples(file: String) async throws {
        _ = try await send(
            "POST", "/v1/session", token: token(), body: ContractTests.data("v1/examples/session.request.json"))
        let body = try ContractTests.data("v1/examples/invalid/\(file)")
        let reply = try await send("POST", "/v1/feedback", token: token(), body: body)
        #expect(reply.status == 400)
        #expect(try errorCode(reply.body) == "invalid_request")
        #expect(backend.supportTickets.isEmpty)
    }

    @Test func theFeedbackGoldenRequestGetsTheContractsShape() async throws {
        _ = try await send(
            "POST", "/v1/session", token: token(), body: ContractTests.data("v1/examples/session.request.json"))
        let reply = try await send(
            "POST", "/v1/feedback", token: token(), body: ContractTests.data("v1/examples/feedback.request.json"))
        #expect(reply.status == 202)
        let receipt = try JSONDecoder().decode(APIV1.FeedbackReceipt.self, from: reply.body)
        #expect(receipt.ticket.ref.wholeMatch(of: /NK-[0-9A-F]{8}/) != nil)
        #expect(receipt.ticket.hasAttachment)
        #expect(APIV1.parseDate(receipt.ticket.receivedAt) != nil)
        // A note needs a token and an account, and no App Attest.
        let anonymous = try await send(
            "POST", "/v1/feedback", body: ContractTests.data("v1/examples/feedback.request.json"))
        #expect(anonymous.status == 401)
    }

    @Test func theDeletionGoldenRequestGetsTheContractsShape() async throws {
        _ = try await send(
            "POST", "/v1/session", token: token(), body: ContractTests.data("v1/examples/session.request.json"))
        let reply = try await send(
            "POST", "/v1/account/deletion", token: token(),
            body: ContractTests.data("v1/examples/deletion.request.json"))
        #expect(reply.status == 202)
        let status = try JSONDecoder().decode(APIV1.DeletionStatus.self, from: reply.body)
        #expect(status.deletion.state == "completed")
        // Without a token, by ID; an unknown ID is not_found.
        let read = try await send(
            "POST", "/v1/account/deletion/status",
            body: try APIV1.encoder().encode(APIV1.DeletionStatusRequest(deletionId: status.deletion.id)))
        #expect(read.status == 200)
        let unknown = try await send(
            "POST", "/v1/account/deletion/status", body: ContractTests.data("v1/examples/deletion-status.request.json"))
        #expect(unknown.status == 404)
        // The deleted sign-in's token no longer works.
        let after = try await send("GET", "/v1/me", token: token())
        #expect(after.status == 401)
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
        // Only a note may be larger than 64 KiB, up to its own limit.
        _ = try await send("POST", "/v1/session", token: token(), body: body)
        let note = try await send("POST", "/v1/feedback", token: token(), body: big)
        #expect(try errorCode(note.body) == "invalid_request")
        let huge = Data(repeating: 0x61, count: APIV1.sendFeedback.maxBodyBytes + 1)
        let tooBig = try await send("POST", "/v1/feedback", token: token(), body: huge)
        #expect(try errorCode(tooBig.body) == "payload_too_large")
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
