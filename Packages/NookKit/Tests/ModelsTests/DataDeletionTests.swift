import Foundation
import Models
import Testing

/// Delete my data's service (Phase 14b): every part is erased through its store, a part that
/// fails doesn't stop the others, and the report says exactly what's left.
struct DataDeletionTests {
    /// A store that records when it was erased and can be told to fail.
    private actor FakeStore: ErasableStore {
        let name: String
        let log: Log
        var failsNext: Bool

        init(_ name: String, log: Log, fails: Bool = false) {
            self.name = name
            self.log = log
            failsNext = fails
        }

        func eraseAll() async throws(StoreError) {
            await log.add(name)
            if failsNext {
                failsNext = false
                throw .unavailable
            }
        }
    }

    private actor Log {
        private(set) var names: [String] = []
        func add(_ name: String) { names.append(name) }
    }

    @Test func erasesEveryStoreInOrderAndReportsEachPart() async {
        let log = Log()
        let deletion = LocalDataDeletion(stores: [
            (.drafts, FakeStore("drafts", log: log)),
            (.drafts, FakeStore("lookDrafts", log: log)),
            (.pictures, FakeStore("pictures", log: log)),
            (.profile, FakeStore("profile", log: log)),
        ])
        #expect(deletion.scopes == [.thisDevice])
        #expect(deletion.parts(in: .thisDevice) == [.drafts, .pictures, .profile])

        let report = await deletion.delete(.thisDevice)
        #expect(await log.names == ["drafts", "lookDrafts", "pictures", "profile"])
        #expect(report.isComplete)
        #expect(report.order == [.drafts, .pictures, .profile])
        #expect(report.failedParts.isEmpty)
        #expect(report.pendingParts.isEmpty)
    }

    @Test func aFailingPartDoesntStopTheOthers() async {
        let log = Log()
        let deletion = LocalDataDeletion(stores: [
            (.pictures, FakeStore("pictures", log: log, fails: true)),
            (.closet, FakeStore("closet", log: log)),
        ])
        let report = await deletion.delete(.thisDevice)
        #expect(await log.names == ["pictures", "closet"])
        #expect(!report.isComplete)
        #expect(report.failedParts == [.pictures])
        #expect(report.outcomes[.closet] == .deleted)

        // Deleting again is safe and finishes the job.
        let again = await deletion.delete(.thisDevice)
        #expect(again.isComplete)
    }

    @Test func aPartHeldByTwoStoresFailsIfEitherFails() async {
        let log = Log()
        let deletion = LocalDataDeletion(stores: [
            (.drafts, FakeStore("drafts", log: log)),
            (.drafts, FakeStore("lookDrafts", log: log, fails: true)),
        ])
        let report = await deletion.delete(.thisDevice)
        #expect(report.order == [.drafts])
        #expect(report.failedParts == [.drafts])
    }

    @Test func aPendingPartIsntComplete() {
        // Phase 24c: a server part can be asked for and not confirmed yet.
        let report = DeletionReport(scope: .thisDevice, results: [(.closet, .deleted), (.profile, .pending)])
        #expect(!report.isComplete)
        #expect(report.pendingParts == [.profile])
        #expect(report.failedParts.isEmpty)
    }

    @Test func theServicesBundleCoversEveryPart() {
        // Every part of her data has a store behind it; nothing is left out of Delete my data.
        // The parts held elsewhere (24c) belong to Delete my account only.
        let parts = Set(DataPart.allCases.filter { !$0.isRemote })
        #expect(parts == [.closet, .looks, .pictures, .suitcases, .profile, .drafts])
        #expect(Set(DataPart.allCases.filter(\.isRemote)) == [.serverData, .account, .signInWithApple, .iCloudCopy])
    }
}

/// Send feedback's note (Phase 14b, PRD §22): her words only, details only when she adds them.
struct FeedbackRulesTests {
    private let details = FeedbackDiagnostics(
        appVersion: "0.1", build: "14", systemVersion: "26.5", deviceModel: "iPhone13,2")

    @Test func trimsHerWordsAndLeavesDetailsOutByDefault() throws {
        let note = try FeedbackRules.note(
            kind: .idea, message: "  Show the hamper's pieces.\n", includeDiagnostics: false, diagnostics: details)
        #expect(note.message == "Show the hamper's pieces.")
        #expect(note.kind == .idea)
        #expect(note.diagnostics == nil)
    }

    @Test func addsDetailsOnlyWhenAsked() throws {
        let note = try FeedbackRules.note(
            kind: .other, message: "Hi", includeDiagnostics: true, diagnostics: details)
        #expect(note.diagnostics == details)
    }

    @Test func refusesAnEmptyOrTooLongNote() {
        #expect(throws: FeedbackProblem.empty) {
            try FeedbackRules.note(kind: .idea, message: " \n ", includeDiagnostics: false, diagnostics: details)
        }
        let long = String(repeating: "a", count: FeedbackRules.maximumLength + 1)
        #expect(throws: FeedbackProblem.tooLong(maximum: 1000)) {
            try FeedbackRules.note(kind: .idea, message: long, includeDiagnostics: false, diagnostics: details)
        }
        let longest = String(repeating: "a", count: FeedbackRules.maximumLength)
        #expect(
            (try? FeedbackRules.note(kind: .idea, message: longest, includeDiagnostics: false, diagnostics: details))
                != nil)
    }
}
