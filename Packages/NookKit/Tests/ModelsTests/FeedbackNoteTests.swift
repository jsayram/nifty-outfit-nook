import Foundation
import Models
import Testing

/// The Send feedback note (Phase 24d): its rules, what it counts as sent, the draft that keeps it,
/// and the support page's address.
struct FeedbackNoteTests {
    private let details = FeedbackDiagnostics(
        appVersion: "0.1", build: "14", systemVersion: "26.5", deviceModel: "iPhone13,2")

    @Test(arguments: ["lily@example.com", "lily.k+nook@mail.example.co.uk", "a@b.io"])
    func realAddressesPass(_ address: String) {
        #expect(FeedbackRules.isEmailAddress(address))
    }

    @Test(arguments: [
        "", "lily", "lily@", "@example.com", "lily@example", "lily at example.com", "lily@exa mple.com",
        "lily@example.com\nBcc: x@example.com", "\"lily\"@example.com", "<lily@example.com>", "a@b.c",
        String(repeating: "a", count: 250) + "@example.com",
    ])
    func notAddressesFail(_ address: String) {
        #expect(!FeedbackRules.isEmailAddress(address))
    }

    @Test func aReplyAddressIsTrimmedAndOptional() throws {
        let none = try FeedbackRules.note(kind: .idea, message: "Hi", includeDiagnostics: false, diagnostics: details)
        #expect(none.replyAddress == nil)
        let blank = try FeedbackRules.note(
            kind: .idea, message: "Hi", includeDiagnostics: false, diagnostics: details, replyAddress: "   ")
        #expect(blank.replyAddress == nil)
        let given = try FeedbackRules.note(
            kind: .idea, message: "Hi", includeDiagnostics: false, diagnostics: details,
            replyAddress: " lily@example.com ")
        #expect(given.replyAddress == "lily@example.com")
        #expect(throws: FeedbackProblem.badReplyAddress) {
            try FeedbackRules.note(
                kind: .idea, message: "Hi", includeDiagnostics: false, diagnostics: details, replyAddress: "lily")
        }
        // Her words come first: an empty note says so even with a bad address.
        #expect(throws: FeedbackProblem.empty) {
            try FeedbackRules.note(
                kind: .idea, message: " ", includeDiagnostics: false, diagnostics: details, replyAddress: "lily")
        }
    }

    @Test func theNoteListsEverythingItSends() throws {
        let plain = FeedbackNote(kind: .other, message: "Words")
        #expect(plain.sentValues == ["Words"])
        let full = FeedbackNote(
            kind: .other, message: "Words", diagnostics: details, replyAddress: "lily@example.com",
            closetCounts: FeedbackClosetCounts(pieces: 42, looks: 9, suitcases: 2),
            screenshot: FeedbackScreenshot(data: Data([1]), pixelWidth: 1, pixelHeight: 1))
        #expect(
            full.sentValues == ["Words", "lily@example.com", "0.1", "14", "26.5", "iPhone13,2", "42", "9", "2"])
    }

    // MARK: The draft

    @Test func aDraftKeptBefore24dStillReadsBack() throws {
        let old = Data(#"{"kind":"idea","message":"A hamper idea","includesDetails":true}"#.utf8)
        let draft = try JSONDecoder().decode(FeedbackDraft.self, from: old)
        #expect(draft == FeedbackDraft(kind: .idea, message: "A hamper idea", includesDetails: true))
        #expect(draft.replyAddress.isEmpty && !draft.includesClosetCounts)
    }

    @Test func aDraftWithoutTheNewFieldsIsWrittenAsItAlwaysWas() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = try encoder.encode(FeedbackDraft(kind: .idea, message: "Hi", includesDetails: true))
        #expect(String(decoding: plain, as: UTF8.self) == #"{"includesDetails":true,"kind":"idea","message":"Hi"}"#)
        let more = FeedbackDraft(message: "Hi", replyAddress: "lily@example.com", includesClosetCounts: true)
        let round = try JSONDecoder().decode(FeedbackDraft.self, from: encoder.encode(more))
        #expect(round == more)
    }

    // MARK: Submissions and the support page

    @Test func submissionIDsAreRandomAndWithinTheContract() {
        let ids = (0..<20).map { _ in FeedbackSubmission.newID() }
        #expect(Set(ids).count == 20)
        for id in ids { #expect(id.wholeMatch(of: /[A-Za-z0-9_-]{16,64}/) != nil, "\(id)") }
    }

    @Test func theSupportPageIsAPlaceholderUntilConfigured() {
        #expect(SupportLinks().supportPage.absoluteString == "https://niftyoutfitnook.pages.dev/support")
        #expect(SupportLinks(info: [:]) == SupportLinks())
        #expect(SupportLinks(info: [SupportLinks.infoKey: ""]) == SupportLinks())
        // An unexpanded build setting, a web address that isn't https, or one with a query: ignored.
        for bad in [
            "$(NOOK_SUPPORT_URL)", "http://example.com/support", "https://example.com/support?id=1", "nonsense",
        ] {
            #expect(SupportLinks(info: [SupportLinks.infoKey: bad]) == SupportLinks(), "\(bad)")
        }
        let set = SupportLinks(info: [SupportLinks.infoKey: " https://nifty.example/support "])
        #expect(set.supportPage.absoluteString == "https://nifty.example/support")
    }
}
