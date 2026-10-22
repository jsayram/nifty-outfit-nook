import Foundation
import NookTestSupport
import Testing

@testable import Models

/// Apple's MetricKit reports, read and cut down (Phase 31). The sample reports below are shaped
/// like `MXDiagnosticPayload.jsonRepresentation()` and `MXMetricPayload.jsonRepresentation()`; none
/// came from a real device (the simulator delivers none), so the parser is also tested on
/// reports with missing, odd and unexpected values.
struct MetricKitParserTests {
    static let received = Date(timeIntervalSince1970: 1_792_000_000)
    static let reportEnd = Date(timeIntervalSince1970: 1_792_540_800)  // 2026-10-21 00:00:00 UTC

    // MARK: Diagnostics

    @Test func everyKindOfEventIsRead() {
        let records = MetricKitParser.diagnostics(from: DiagnosticsSamples.diagnosticReport, receivedAt: Self.received)
        #expect(records.map(\.kind) == [.crash, .crash, .hang, .cpuException, .diskWriteException, .slowLaunch])
        #expect(Set(records.map(\.id)).count == records.count)
        #expect(records.allSatisfy { $0.at == Self.reportEnd })
        let first = records[0]
        #expect(first.exception == .badAccess && first.signal == .sigsegv)
        #expect(first.appVersion == "0.1" && first.build == "14" && first.systemVersion == "26.5")
        #expect(first.deviceModel == "iPhone13,2")
        #expect(records[1].exception == .breakpoint && records[1].signal == .sigtrap)
        #expect(records[2].durationMs == 2400)
        #expect(records[5].durationMs == 6500)
    }

    @Test func theSameReportReadTwiceMakesTheSameIDs() {
        let a = MetricKitParser.diagnostics(from: DiagnosticsSamples.diagnosticReport, receivedAt: Self.received)
        let b = MetricKitParser.diagnostics(
            from: DiagnosticsSamples.diagnosticReport, receivedAt: Self.received.addingTimeInterval(500))
        #expect(a.map(\.id) == b.map(\.id))
    }

    @Test func aReportWithoutTimesIsDatedByWhenItArrived() {
        let json = Data(#"{"hangDiagnostics": [{"diagnosticMetaData": {"hangDuration": 5000}}]}"#.utf8)
        let records = MetricKitParser.diagnostics(from: json, receivedAt: Self.received)
        #expect(records.count == 1 && records[0].at == Self.received)
        // A bare number is milliseconds.
        #expect(records[0].durationMs == 5000)
    }

    // MARK: Metrics

    @Test func aMetricReportGivesAFewNumbers() throws {
        let sample = try #require(
            MetricKitParser.metrics(from: DiagnosticsSamples.metricReport, receivedAt: Self.received))
        #expect(sample.end == Self.reportEnd && sample.begin == Self.reportEnd.addingTimeInterval(-86_400))
        // 8 launches; the middle one (the 4th) is in the 400 to 800 ms bucket, so about 600 ms.
        #expect(sample.launchMedianMs == 600)
        #expect(sample.resumeMedianMs == 100)
        #expect(sample.peakMemoryMB == 310)
        // Memory: 1 in the foreground, 3 in the background (memory pressure). Watchdog: 2 + 1.
        #expect(sample.memoryExits == 4 && sample.watchdogExits == 3 && sample.abnormalExits == 3)
        #expect(sample.appVersion == "0.1" && sample.build == "14" && sample.systemVersion == "26.5")
    }

    // MARK: Bad input

    @Test(arguments: [
        "", "not json", "[]", "null", "42", "{", "{\"crashDiagnostics\": \"x\"}",
        "{\"crashDiagnostics\": [1, null, \"a\"]}",
    ])
    func garbageGivesNothingAndNeverCrashes(_ text: String) {
        #expect(MetricKitParser.diagnostics(from: Data(text.utf8), receivedAt: Self.received).isEmpty)
        #expect(MetricKitParser.metrics(from: Data(text.utf8), receivedAt: Self.received) == nil)
    }

    @Test func oddValuesAreSkippedNotGuessed() throws {
        let json = Data(
            """
            {"timeStampEnd": "yesterday-ish", "crashDiagnostics": [{"diagnosticMetaData": {
              "exceptionType": "lots", "signal": 99, "appVersion": "1.0 (beta) with spaces", "appBuildVersion": "x/y",
              "deviceType": "iPhone 12 of Maria", "osVersion": "no digits here"}}],
             "hangDiagnostics": [{"diagnosticMetaData": {"hangDuration": "soon"}}, {"diagnosticMetaData": {"hangDuration": "3 fortnights"}},
              {"diagnosticMetaData": {"hangDuration": "-4 sec"}}, {"diagnosticMetaData": {"hangDuration": true}}]}
            """.utf8)
        let records = MetricKitParser.diagnostics(from: json, receivedAt: Self.received)
        let crash = try #require(records.first)
        #expect(crash.at == Self.received)
        #expect(crash.exception == CrashExceptionKind.other && crash.signal == CrashSignalKind.other)
        #expect(crash.appVersion == nil && crash.build == nil && crash.deviceModel == nil && crash.systemVersion == nil)
        #expect(records.dropFirst().allSatisfy { $0.durationMs == nil })
    }

    @Test func aMetricDocumentWithNoMetricPartsIsNotOne() {
        #expect(
            MetricKitParser.metrics(
                from: Data(#"{"timeStampEnd": "2026-10-21 00:00:00 +0000"}"#.utf8), receivedAt: Self.received) == nil)
        let bare = Data(#"{"memoryMetrics": {"peakMemoryUsage": "1 GB"}}"#.utf8)
        #expect(MetricKitParser.metrics(from: bare, receivedAt: Self.received)?.peakMemoryMB == 1000)
    }

    @Test func unitsAreConverted() {
        #expect(MetricKitParser.milliseconds("1.5 sec") == 1500)
        #expect(MetricKitParser.milliseconds("2 min") == 120_000)
        #expect(MetricKitParser.milliseconds("250 ms") == 250)
        #expect(MetricKitParser.milliseconds("2000 µs") == 2)
        #expect(MetricKitParser.milliseconds("1e12 sec") == nil)
        #expect(MetricKitParser.megabytes("512000 kB") == 512)
        #expect(MetricKitParser.megabytes("2 GB") == 2000)
        #expect(MetricKitParser.megabytes("3 MiB") == 3)
        #expect(MetricKitParser.megabytes(250_000_000) == 250)
        #expect(MetricKitParser.megabytes("many") == nil)
    }

    @Test func machNumbersBecomeFixedNames() {
        let exceptions = [1, 2, 3, 5, 6, 7, 10, 11, 12, 99].map { CrashExceptionKind(machType: $0) }
        #expect(
            exceptions == [
                .badAccess, .badInstruction, .arithmetic, .software, .breakpoint, .syscall, .crash, .resource, .guard,
                .other,
            ])
        #expect(CrashExceptionKind(machType: nil) == .other)
        let signals = [nil, 0, 4, 5, 6, 8, 9, 10, 11, 13, 15, 31].map { CrashSignalKind(number: $0) }
        #expect(
            signals == [
                .none, .none, .sigill, .sigtrap, .sigabrt, .sigfpe, .sigkill, .sigbus, .sigsegv, .sigpipe, .sigterm,
                .other,
            ])
    }

    // MARK: Redaction

    @Test func nothingPersonalSurvivesParsing() throws {
        let records = MetricKitParser.diagnostics(from: DiagnosticsSamples.diagnosticReport, receivedAt: Self.received)
        let sample = try #require(
            MetricKitParser.metrics(from: DiagnosticsSamples.metricReport, receivedAt: Self.received))
        let encoder = JSONEncoder()
        let kept = try String(decoding: encoder.encode(records) + encoder.encode(sample), as: UTF8.self)
        for secret in DiagnosticsSamples.planted {
            #expect(!kept.contains(secret), "“\(secret)” was kept")
        }
        // And the summary, which is the only thing that can leave the phone.
        let snapshot = DiagnosticsSnapshot(
            since: Self.reportEnd.addingTimeInterval(-86_400), records: records, samples: [sample])
        let summary = try #require(snapshot.summary(now: Self.reportEnd.addingTimeInterval(3600)))
        let shared =
            try String(decoding: encoder.encode(summary), as: UTF8.self) + summary.sentValues.joined(separator: " ")
        for secret in DiagnosticsSamples.planted + ["14", "0.1", "iPhone13,2", "26.5"] {
            #expect(!shared.contains(secret), "“\(secret)” would be shared")
        }
    }

    @Test func recordsHaveOnlyFixedFields() throws {
        let records = MetricKitParser.diagnostics(from: DiagnosticsSamples.diagnosticReport, receivedAt: Self.received)
        let sample = try #require(
            MetricKitParser.metrics(from: DiagnosticsSamples.metricReport, receivedAt: Self.received))
        let allowedRecord: Set<String> = [
            "id", "kind", "at", "appVersion", "build", "systemVersion", "deviceModel", "exception", "signal",
            "durationMs",
        ]
        let allowedSample: Set<String> = [
            "id", "begin", "end", "appVersion", "build", "systemVersion", "deviceModel", "launchMedianMs",
            "resumeMedianMs",
            "peakMemoryMB", "memoryExits", "watchdogExits", "abnormalExits",
        ]
        for record in records {
            let keys = try #require(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
            ).keys
            #expect(Set(keys).isSubset(of: allowedRecord))
        }
        let keys = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
            .keys
        #expect(Set(keys).isSubset(of: allowedSample))
    }
}
