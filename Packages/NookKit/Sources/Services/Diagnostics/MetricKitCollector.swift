import Foundation
import Models

#if canImport(MetricKit)
    import MetricKit

    /// Receives Apple's MetricKit reports and hands them to the `DiagnosticsLog` (Phase 31).
    ///
    /// MetricKit is Apple's own crash and performance reporting: the system collects it on the
    /// phone, and the app is handed a report about once a day (crashes and hangs as soon as the
    /// next launch). Nothing is sent anywhere from here, and no third-party code is involved. The
    /// raw reports are read and cut down (`MetricKitParser`) the moment they arrive, so call
    /// stacks and the rest are never stored.
    ///
    /// Apple's own route stays separate and needs nothing from the app: when she has "Share With
    /// App Developers" on in Settings, Privacy & Security, Analytics & Improvements, crash reports
    /// reach Xcode Organizer and TestFlight, and Apple shows Jose only what it collects.
    ///
    /// MetricKit's `MXMetricManager` is marked for deprecation in favour of `MetricManager` (iOS
    /// 27 and later). It works on every iOS this app supports; moving to the new one is a later
    /// change, once iOS 26 is no longer a target.
    public final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
        private let log: any DiagnosticsReading

        public init(log: any DiagnosticsReading) {
            self.log = log
            super.init()
        }

        /// Starts listening, and reads any reports MetricKit kept since the last launch.
        public func start() {
            let manager = MXMetricManager.shared
            manager.add(self)
            let metrics = manager.pastPayloads.map { $0.jsonRepresentation() }
            let diagnostics = manager.pastDiagnosticPayloads.map { $0.jsonRepresentation() }
            ingest(diagnostics: diagnostics, metrics: metrics)
        }

        public func stop() {
            MXMetricManager.shared.remove(self)
        }

        public func didReceive(_ payloads: [MXMetricPayload]) {
            ingest(diagnostics: [], metrics: payloads.map { $0.jsonRepresentation() })
        }

        public func didReceive(_ payloads: [MXDiagnosticPayload]) {
            ingest(diagnostics: payloads.map { $0.jsonRepresentation() }, metrics: [])
        }

        private func ingest(diagnostics: [Data], metrics: [Data]) {
            guard !diagnostics.isEmpty || !metrics.isEmpty else { return }
            let log = log
            Task.detached(priority: .utility) {
                await log.ingest(diagnosticPayloads: diagnostics, metricPayloads: metrics)
            }
        }
    }
#endif
