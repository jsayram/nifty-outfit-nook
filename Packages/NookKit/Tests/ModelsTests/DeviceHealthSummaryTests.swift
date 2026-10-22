import Foundation
import Models
import Testing

/// The summary she can share (Phase 31): how the kept records add up, the window, the limits, and
/// that every value in it is one she can read.
struct DeviceHealthSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_792_800_000)  // 2026-10-24
    private func day(_ ago: Int) -> Date { now.addingTimeInterval(-Double(ago) * 86_400) }

    private func crash(
        _ ago: Int, _ exception: CrashExceptionKind = .badAccess, _ signal: CrashSignalKind = .sigsegv,
        id: String? = nil
    )
        -> DiagnosticRecord
    {
        DiagnosticRecord(
            id: id ?? "crash-\(ago)-\(exception)-\(signal)", kind: .crash, at: day(ago), exception: exception,
            signal: signal)
    }

    @Test func recordsAddUp() throws {
        let records = [
            crash(1), crash(2), crash(3, .breakpoint, .sigtrap),
            DiagnosticRecord(id: "h1", kind: .hang, at: day(1), durationMs: 2400),
            DiagnosticRecord(id: "h2", kind: .hang, at: day(2), durationMs: 5100),
            DiagnosticRecord(id: "c1", kind: .cpuException, at: day(2)),
            DiagnosticRecord(id: "d1", kind: .diskWriteException, at: day(4)),
        ]
        let samples = [
            MetricSample(id: "m1", begin: day(2), end: day(1), launchMedianMs: 500, peakMemoryMB: 280, memoryExits: 1),
            MetricSample(
                id: "m2", begin: day(3), end: day(2), launchMedianMs: 700, peakMemoryMB: 310, watchdogExits: 2),
            MetricSample(id: "m3", begin: day(4), end: day(3), launchMedianMs: 600),
        ]
        let summary = try #require(
            DiagnosticsSnapshot(since: day(10), records: records, samples: samples).summary(now: now))
        #expect(
            summary.crashes == 3 && summary.hangs == 2 && summary.cpuExceptions == 1 && summary.diskWriteExceptions == 1
        )
        #expect(summary.memoryExits == 1 && summary.watchdogExits == 2)
        #expect(summary.longestHangMs == 5100 && summary.launchMedianMs == 600 && summary.peakMemoryMB == 310)
        #expect(summary.windowDays == 11)
        // Most frequent first.
        #expect(
            summary.crashKinds == [
                .init(exception: .badAccess, signal: .sigsegv, count: 2),
                .init(exception: .breakpoint, signal: .sigtrap, count: 1),
            ])
        #expect(summary.isWithinContract)
    }

    @Test func nothingToSayIsNoSummary() {
        #expect(DiagnosticsSnapshot(since: day(3)).summary(now: now) == nil)
        // Only old events: nothing in the last 30 days.
        let old = DiagnosticsSnapshot(since: day(90), records: [crash(45)], samples: [])
        #expect(old.summary(now: now) == nil)
    }

    @Test func theWindowIsAtMostThirtyDaysAndAtLeastOne() throws {
        let a = try #require(DiagnosticsSnapshot(since: day(200), records: [crash(1)]).summary(now: now))
        #expect(a.windowDays == 30)
        let b = try #require(DiagnosticsSnapshot(since: now, records: [crash(0)]).summary(now: now))
        #expect(b.windowDays == 1)
    }

    @Test func crashKindsAreCappedAtEightAndSortedStably() throws {
        var records: [DiagnosticRecord] = []
        var number = 0
        for exception in CrashExceptionKind.allCases {
            for signal in [CrashSignalKind.sigabrt, .sigsegv] {
                number += 1
                records.append(crash(1, exception, signal, id: "k\(number)"))
            }
        }
        let summary = try #require(DiagnosticsSnapshot(since: day(5), records: records).summary(now: now))
        #expect(summary.crashes == 20)
        #expect(summary.crashKinds.count == DeviceHealthSummary.maximumCrashKinds)
        #expect(summary.isWithinContract)
        let again = DiagnosticsSnapshot(since: day(5), records: records.reversed()).summary(now: now)
        #expect(again == summary)
    }

    @Test func pruningKeepsRecentAndLimitsTheNumber() {
        var records = (0..<250).map {
            DiagnosticRecord(id: "r\($0)", kind: .hang, at: day(1).addingTimeInterval(Double($0)), durationMs: 1)
        }
        records.append(crash(40))
        let samples = (0..<80).map {
            MetricSample(id: "s\($0)", begin: day(2), end: day(1).addingTimeInterval(Double($0)))
        }
        let pruned = DiagnosticsSnapshot(since: day(50), records: records, samples: samples).pruned(now: now)
        #expect(
            pruned.records.count == DiagnosticsSnapshot.maximumRecords
                && pruned.samples.count == DiagnosticsSnapshot.maximumSamples)
        #expect(!pruned.records.contains { $0.kind == .crash }, "40 days old")
        #expect(pruned.records.first?.id == "r249", "newest first")
    }

    @Test func theContractsBoundsAreChecked() {
        #expect(DeviceHealthSummary(windowDays: 14, crashes: 1).isWithinContract)
        #expect(!DeviceHealthSummary(windowDays: 0, crashes: 1).isWithinContract)
        #expect(!DeviceHealthSummary(windowDays: 91).isWithinContract)
        #expect(!DeviceHealthSummary(windowDays: 14, crashes: 10_001).isWithinContract)
        #expect(!DeviceHealthSummary(windowDays: 14, crashes: -1).isWithinContract)
        #expect(!DeviceHealthSummary(windowDays: 14, longestHangMs: 3_600_001).isWithinContract)
        #expect(!DeviceHealthSummary(windowDays: 14, peakMemoryMB: 70_000).isWithinContract)
        let tooMany = (0..<9).map { _ in DeviceHealthSummary.CrashKind(exception: .other, signal: .other, count: 1) }
        #expect(!DeviceHealthSummary(windowDays: 14, crashKinds: tooMany).isWithinContract)
        let wild = DeviceHealthSummary(
            windowDays: 400, crashes: 99_999, longestHangMs: -5, peakMemoryMB: 1 << 40, crashKinds: tooMany)
        #expect(wild.clamped().isWithinContract)
    }

    @Test func sentValuesListEveryNumberAndName() {
        let summary = DeviceHealthSummary(
            windowDays: 14, crashes: 2, hangs: 1, cpuExceptions: 0, diskWriteExceptions: 0, memoryExits: 1,
            watchdogExits: 0,
            longestHangMs: 2400, launchMedianMs: 450, peakMemoryMB: 310,
            crashKinds: [.init(exception: .badAccess, signal: .sigsegv, count: 2)])
        #expect(
            summary.sentValues == [
                "14", "2", "1", "0", "0", "1", "0", "2400", "450", "310", "badAccess", "sigsegv", "2",
            ])
        #expect(DeviceHealthSummary(windowDays: 7, crashes: 1).sentValues == ["7", "1", "0", "0", "0", "0", "0"])
        #expect(!summary.isEmpty && DeviceHealthSummary(windowDays: 7).isEmpty)
    }

    @Test func aNoteCarriesTheSummaryOnlyWhenGivenAndWithinTheContract() throws {
        let details = FeedbackDiagnostics(
            appVersion: "0.1", build: "14", systemVersion: "26.5", deviceModel: "iPhone13,2")
        let health = DeviceHealthSummary(windowDays: 14, crashes: 2)
        let plain = try FeedbackRules.note(kind: .idea, message: "Hi", includeDiagnostics: false, diagnostics: details)
        #expect(plain.deviceHealth == nil && plain.sentValues == ["Hi"])
        let with = try FeedbackRules.note(
            kind: .idea, message: "Hi", includeDiagnostics: false, diagnostics: details, deviceHealth: health)
        #expect(with.deviceHealth == health)
        #expect(with.sentValues == ["Hi"] + health.sentValues)
        let wild = DeviceHealthSummary(windowDays: 14, crashes: 99_999)
        let refused = try FeedbackRules.note(
            kind: .idea, message: "Hi", includeDiagnostics: false, diagnostics: details, deviceHealth: wild)
        #expect(refused.deviceHealth == nil, "a summary the contract would refuse is never sent")
    }
}
