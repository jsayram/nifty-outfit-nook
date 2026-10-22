import Fixtures
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Services

/// The phone's own reports (Phase 31): kept in one small file, only the cut-down fields, for 30
/// days, outside backups, and gone when she deletes her data.
struct DiagnosticsLogTests {
    /// A clock the test moves.
    final class Clock: @unchecked Sendable {
        private let value: Mutex<Date>
        init(_ start: Date) { value = Mutex(start) }
        var now: Date { value.withLock { $0 } }
        func advance(days: Double) { value.withLock { $0 = $0.addingTimeInterval(days * 86_400) } }
    }

    private static let start = Date(timeIntervalSince1970: 1_792_800_000)  // 2026-10-24

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        return url
    }

    private func report(daysAgo: Double, in clock: Clock, crashes: Int = 1) -> Data {
        let end = clock.now.addingTimeInterval(-daysAgo * 86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let events = (0..<crashes).map { _ in
            #"{"diagnosticMetaData": {"appBuildVersion": "14", "exceptionType": 1, "signal": 11, "regionFormat": "US", "pid": 7}}"#
        }.joined(separator: ",")
        return Data(#"{"timeStampEnd": "\#(formatter.string(from: end))", "crashDiagnostics": [\#(events)]}"#.utf8)
    }

    @Test func reportsAreKeptAcrossLaunches() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let first = DiagnosticsLog(directory: directory, now: { clock.now })
        #expect(await first.summary() == nil)
        await first.ingest(diagnosticPayloads: [report(daysAgo: 1, in: clock, crashes: 2)], metricPayloads: [])
        let summary = try #require(await first.summary())
        #expect(
            summary.crashes == 2 && summary.crashKinds == [.init(exception: .badAccess, signal: .sigsegv, count: 2)])

        // A new process reads the same file.
        let second = DiagnosticsLog(directory: directory, now: { clock.now })
        #expect(await second.summary() == summary)
        #expect(await second.snapshot().records.count == 2)
    }

    @Test func theSameReportIsKeptOnce() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        let one = report(daysAgo: 1, in: clock)
        await log.ingest(diagnosticPayloads: [one], metricPayloads: [])
        await log.ingest(diagnosticPayloads: [one, one], metricPayloads: [])
        #expect(await log.snapshot().records.count == 1)
    }

    @Test func oldReportsAgeOutAfterThirtyDays() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        await log.ingest(diagnosticPayloads: [report(daysAgo: 1, in: clock)], metricPayloads: [])
        #expect(await log.summary()?.crashes == 1)
        clock.advance(days: 29)
        #expect(await log.summary()?.crashes == 1, "30 days old, still counted")
        clock.advance(days: 2)
        #expect(await log.summary() == nil)
        #expect(await log.snapshot().records.isEmpty)
        // The next report written drops what aged out of the file too.
        await log.ingest(diagnosticPayloads: [report(daysAgo: 0, in: clock)], metricPayloads: [])
        let reopened = DiagnosticsLog(directory: directory, now: { clock.now })
        #expect(await reopened.snapshot().records.count == 1)
    }

    @Test func theFileHoldsOnlyTheCutDownFields() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        await log.ingest(
            diagnosticPayloads: [DiagnosticsSamples.diagnosticReport], metricPayloads: [DiagnosticsSamples.metricReport]
        )
        let file = try String(contentsOf: directory.appending(path: "reports.json"), encoding: .utf8)
        #expect(file.contains("badAccess"))
        for secret in DiagnosticsSamples.planted {
            #expect(!file.contains(secret), "“\(secret)” is in the file")
        }
    }

    @Test func theFileIsLeftOutOfBackupsAndHasFileProtection() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        await log.ingest(diagnosticPayloads: [report(daysAgo: 1, in: clock)], metricPayloads: [])
        let file = directory.appending(path: "reports.json")
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #if !targetEnvironment(simulator)
            let protection =
                try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType
            #expect(protection == .completeUntilFirstUserAuthentication)
        #endif
    }

    @Test func aDamagedFileStartsFresh() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: directory.appending(path: "reports.json"))
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        #expect(await log.summary() == nil)
        await log.ingest(diagnosticPayloads: [report(daysAgo: 1, in: clock)], metricPayloads: [])
        #expect(await log.summary()?.crashes == 1)
    }

    @Test func garbageInGarbageOutKeepsNothing() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        await log.ingest(diagnosticPayloads: [Data("nope".utf8), Data()], metricPayloads: [Data("[]".utf8)])
        #expect(await log.summary() == nil)
        let kept = await log.snapshot()
        #expect(kept.records.isEmpty && kept.samples.isEmpty)
    }

    @Test func deleteMyDataRemovesTheFileAndStartsOver() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        await log.ingest(diagnosticPayloads: [report(daysAgo: 1, in: clock)], metricPayloads: [])
        try await log.eraseAll()
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "reports.json").path))
        #expect(await log.summary() == nil)
        try await log.eraseAll()  // erasing nothing is fine
        // The window starts again from the day it was cleared (3 days ago, so 4 days counting today).
        clock.advance(days: 3)
        await log.ingest(diagnosticPayloads: [report(daysAgo: 0, in: clock)], metricPayloads: [])
        #expect(await log.summary()?.windowDays == 4)
    }

    @Test func deleteMyDataReachesItThroughTheServices() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Self.start)
        let log = DiagnosticsLog(directory: directory, now: { clock.now })
        await log.ingest(diagnosticPayloads: [report(daysAgo: 1, in: clock)], metricPayloads: [])
        var services = FixtureServices.make(FixtureConfiguration(set: .empty))
        services.diagnostics = log
        // The standard deletion lists it, under the unsent-work part, and empties it.
        let deletion = services.deletion
        #expect(deletion.parts(in: .thisDevice).contains(.drafts))
        let report = await deletion.delete(.thisDevice)
        #expect(report.isLocalComplete)
        #expect(await log.summary() == nil)
        // Services that collect nothing delete exactly as before.
        var plain = FixtureServices.make(FixtureConfiguration(set: .empty))
        plain.diagnostics = nil
        #expect(await plain.deletion.delete(.thisDevice).isLocalComplete)
    }
}
