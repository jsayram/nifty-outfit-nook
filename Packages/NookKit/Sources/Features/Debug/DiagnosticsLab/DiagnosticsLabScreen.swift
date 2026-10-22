#if DEBUG
    import Models
    import Observation
    import SwiftUI

    /// The Phase 31 diagnostics screen: what the phone has kept from Apple's MetricKit reports, and
    /// the summary that "Share crash and speed details" on Send feedback would add to a note.
    ///
    /// Debug builds only: launch with `-diagnostics-lab`. Real reports arrive about once a day on a
    /// device; "Add sample reports" stands in for them, with text in them that must not be kept.
    public struct DiagnosticsLabScreen: View {
        @State private var model: DiagnosticsLabModel

        public init(log: any DiagnosticsReading) {
            _model = State(initialValue: DiagnosticsLabModel(log: log))
        }

        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        if let summary = model.summary {
                            ForEach(FeedbackText.healthLines(summary), id: \.self) { line in
                                Text(verbatim: line).font(.footnote.monospaced())
                            }
                        } else {
                            Text(verbatim: "Nothing to share yet.").accessibilityIdentifier("diagnosticsLab.empty")
                        }
                    } header: {
                        Text(verbatim: "What a note would carry if she turned it on")
                    }
                    Section {
                        Button {
                            Task { await model.addSamples() }
                        } label: {
                            Text(verbatim: "Add sample reports")
                        }
                        .accessibilityIdentifier("diagnosticsLab.add")
                        Button(role: .destructive) {
                            Task { await model.clear() }
                        } label: {
                            Text(verbatim: "Clear everything")
                        }
                        .accessibilityIdentifier("diagnosticsLab.clear")
                    }
                    Section {
                        if model.snapshot.records.isEmpty { Text(verbatim: "No events.") }
                        ForEach(model.snapshot.records) { record in
                            Text(verbatim: describe(record)).font(.footnote.monospaced())
                        }
                    } header: {
                        Text(verbatim: "Events (\(model.snapshot.records.count))")
                    }
                    Section {
                        if model.snapshot.samples.isEmpty { Text(verbatim: "No daily samples.") }
                        ForEach(model.snapshot.samples) { sample in
                            Text(verbatim: describe(sample)).font(.footnote.monospaced())
                        }
                    } header: {
                        Text(verbatim: "Daily samples (\(model.snapshot.samples.count))")
                    }
                    Section {
                        Text(
                            verbatim:
                                "Kept on this phone for 30 days, outside backups. Nothing is sent unless she turns on Share crash and speed details on one note. Apple's own crash reports reach Xcode Organizer only if she has Share With App Developers on in Settings."
                        )
                        .font(.footnote)
                    }
                }
                .navigationTitle(Text(verbatim: "Diagnostics"))
                .task { await model.reload() }
            }
            .accessibilityIdentifier("diagnosticsLab")
        }

        private func describe(_ record: DiagnosticRecord) -> String {
            var parts = [record.kind.rawValue, record.at.formatted(date: .abbreviated, time: .omitted)]
            if let exception = record.exception { parts.append(exception.rawValue) }
            if let signal = record.signal { parts.append(signal.rawValue) }
            if let duration = record.durationMs { parts.append("\(duration) ms") }
            parts.append(
                [record.appVersion, record.build, record.systemVersion, record.deviceModel].compactMap { $0 }.joined(
                    separator: " "))
            return parts.joined(separator: " | ")
        }

        private func describe(_ sample: MetricSample) -> String {
            var parts = [sample.end.formatted(date: .abbreviated, time: .omitted)]
            if let launch = sample.launchMedianMs { parts.append("start \(launch) ms") }
            if let resume = sample.resumeMedianMs { parts.append("resume \(resume) ms") }
            if let memory = sample.peakMemoryMB { parts.append("peak \(memory) MB") }
            parts.append(
                "memory exits \(sample.memoryExits), watchdog \(sample.watchdogExits), abnormal \(sample.abnormalExits)"
            )
            return parts.joined(separator: " | ")
        }
    }

    @MainActor
    @Observable
    final class DiagnosticsLabModel {
        private(set) var snapshot = DiagnosticsSnapshot(since: .now)
        private(set) var summary: DeviceHealthSummary?
        @ObservationIgnored private let log: any DiagnosticsReading

        init(log: any DiagnosticsReading) {
            self.log = log
        }

        func reload() async {
            snapshot = await log.snapshot()
            summary = await log.summary()
        }

        func addSamples() async {
            await log.ingest(
                diagnosticPayloads: [
                    DiagnosticsSampleReports.diagnostics(daysAgo: 1), DiagnosticsSampleReports.diagnostics(daysAgo: 3),
                ],
                metricPayloads: [
                    DiagnosticsSampleReports.metrics(daysAgo: 1), DiagnosticsSampleReports.metrics(daysAgo: 2),
                ])
            await reload()
        }

        func clear() async {
            try? await log.eraseAll()
            await reload()
        }
    }
#endif
