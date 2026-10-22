import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// Where Phase 27c keeps its jobs and Ask stylist conversations: two new kinds of record in the
/// 21a store, so the schema doesn't change. Older stores and backups still open and restore,
/// jobs never leave the iPhone in an export, conversations do, and Delete my data erases both.
@MainActor
struct AIJobsStoreTests {
    static func job(_ key: String = "idem_store_test_00") -> AIJob {
        AIJob(
            kind: .styling, idempotencyKey: key,
            request: .styling(AIJobsTests.context(), consentVersion: "stylist-1"), createdAt: TestTime.now)
    }

    static func thread() -> StylistThread {
        var thread = StylistThread(lookID: "look-1", createdAt: TestTime.now)
        thread.append(.init(from: .her, text: "Is this too much for the office?", at: TestTime.now))
        thread.append(.init(from: .stylist, text: "No, it's smart.", pieces: ["g-1"], at: TestTime.now))
        return thread
    }

    @Test func jobsAndConversationsSurviveARelaunch() async throws {
        let store = try TemporaryStore("relaunch")
        let job = Self.job()
        let thread = Self.thread()
        do {
            let storage = try store.open()
            try await storage.aiJobs.save(job)
            try await storage.stylistThreads.save(thread)
        }
        let relaunched = try store.open()
        #expect(try await relaunched.aiJobs.jobs() == [job])
        #expect(try await relaunched.stylistThreads.thread(thread.id) == thread)
        #expect(try await relaunched.stylistThreads.thread(about: "look-1") == thread)
        try await relaunched.aiJobs.remove([job.id])
        #expect(try await relaunched.aiJobs.jobs().isEmpty)
    }

    /// The Phase 21b store (schema 1) migrates as before, and then holds jobs and conversations
    /// next to every record it had.
    @Test func thePhase21bStoreMigratesThenKeepsJobsAndConversations() async throws {
        let store = try TemporaryStore("21b-jobs")
        try store.location.makeDirectory()
        try FileManager.default.copyItem(at: try Phase21bFixtures.url("Nook-v1", "store"), to: store.location.storeURL)
        let job = Self.job()
        let thread = Self.thread()
        do {
            let storage = try store.open()
            #expect(try await storage.aiJobs.jobs().isEmpty)
            try await storage.aiJobs.save(job)
            try await storage.stylistThreads.save(thread)
        }
        let relaunched = try store.open()
        #expect(try await relaunched.aiJobs.jobs() == [job])
        #expect(try await relaunched.stylistThreads.threads() == [thread])
        let rows = Set(try StoreRow.all(in: ModelContext(relaunched.container)))
        #expect(Set(try Phase21bFixtures.rows()).isSubset(of: rows))
    }

    /// Backups made before 27c have no conversations file. They restore both ways, and a jobs
    /// list on the iPhone is left alone (it's this iPhone's work in progress).
    @Test(arguments: [
        ("records-demo-1", Phase21bFixtures.recordsPassphrase), ("records-demo-21c", Phase21cFixtures.passphrase),
    ])
    func anOlderBackupRestoresAndLeavesTheJobsAlone(fixture: String, passphrase: String) async throws {
        for mode in [RestoreMode.replace, .addMissing] {
            let phone = try BackupTestBed("older-\(fixture)")
            let job = Self.job()
            try await phone.storage.aiJobs.save(job)
            let service = phone.service()
            let preview = try await service.check(
                try Phase21bFixtures.url(fixture, "nookbackup"), passphrase: passphrase)
            #expect(preview.inCopy.pieces > 0)
            _ = try await service.restore(preview, as: mode)
            phone.storage.reload()
            #expect(try await phone.storage.aiJobs.jobs() == [job])
            #expect(try await !phone.storage.closet.garments().isEmpty)
        }
    }

    @Test func anExportCarriesConversationsButNeverJobs() async throws {
        let phone = try BackupTestBed("export")
        try await phone.seedDemo()
        let thread = Self.thread()
        try await phone.storage.stylistThreads.save(thread)
        try await phone.storage.aiJobs.save(Self.job())
        let file = try await phone.export()

        let other = try BackupTestBed("export-other")
        let service = other.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        _ = try await service.restore(preview, as: .replace)
        other.storage.reload()
        #expect(try await other.storage.stylistThreads.threads() == [thread])
        #expect(try await other.storage.aiJobs.jobs().isEmpty)
        #expect(!(try other.rows()).contains { $0.kind == RecordKind.aiJob.rawValue })
    }

    @Test func deleteMyDataErasesJobsAndConversations() async throws {
        let store = try TemporaryStore("erase")
        let storage = try store.open()
        try await storage.aiJobs.save(Self.job())
        try await storage.stylistThreads.save(Self.thread())
        _ = await LocalDataDeletion(stores: storage.erasableData).delete(.thisDevice)
        #expect(try await storage.aiJobs.jobs().isEmpty)
        #expect(try await storage.stylistThreads.threads().isEmpty)
    }
}

/// A backup the build on `develop` made just before Phase 27c (Phase 21c payloads, format 1, no
/// conversations file), made on 22 October 2026 at fd935be with `BackupTestBed.seedDemo()`. Never
/// remake or edit it to make a test pass.
enum Phase21cFixtures {
    static let passphrase = "phase 21c demo backup fixture"
}
