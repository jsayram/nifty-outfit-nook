import Features
import Foundation
import Models
import Services

/// The phone's own crash and speed reports (Phase 31, `docs/monitoring.md`): Apple's MetricKit
/// hands the app a report about once a day; the app keeps a few numbers from it on the phone and
/// nothing leaves unless she turns on "Share crash and speed details" for one feedback note.
/// No third-party crash or analytics library is involved.
@MainActor
enum AppDiagnostics {
    /// The reports kept on the phone, in the app's own folder.
    static let log: any DiagnosticsReading = {
        #if DEBUG
            // The debug diagnostics screen and the UI tests keep their sample reports in a folder of
            // their own, so they never mix with real ones or with another test's.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-diagnostics-lab") || arguments.contains("-diagnostics-sample-reports") {
                return DiagnosticsLog(
                    directory: FileManager.default.temporaryDirectory.appending(
                        path: "diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory))
            }
        #endif
        return DiagnosticsLog()
    }()

    #if DEBUG
        /// `-diagnostics-sample-reports` (debug builds only) starts with sample MetricKit reports, so a
        /// UI test can see the Send feedback switch that offers them.
        static func seedIfAsked(arguments: [String]) async {
            guard arguments.contains("-diagnostics-sample-reports") else { return }
            await log.ingest(
                diagnosticPayloads: [DiagnosticsSampleReports.diagnostics(daysAgo: 1)],
                metricPayloads: [DiagnosticsSampleReports.metrics(daysAgo: 1)])
        }
    #endif

    #if canImport(MetricKit)
        private static let collector = MetricKitCollector(log: log)
    #endif

    /// Starts listening for MetricKit reports and reads any it kept since the last launch. Not in
    /// the hosted unit tests, which run inside the app.
    static func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if canImport(MetricKit)
            collector.start()
        #endif
    }

    static func install(into services: inout NookServices) {
        services.diagnostics = log
    }
}
