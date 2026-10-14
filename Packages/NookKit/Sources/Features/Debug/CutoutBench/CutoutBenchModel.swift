#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import Models
    import Observation

    /// Runs the cutout benchmark (Phase 8a): each photo is cut out twice in a row, timed, with
    /// the app's memory sampled while it runs. Photos are worked on one at a time, so one
    /// photo's memory doesn't hide another's.
    ///
    /// Debug builds only. Nothing is saved or sent: photos stay in memory until the screen goes.
    @Observable
    final class CutoutBenchModel {
        /// A photo to measure.
        struct Input: Sendable {
            var label: String
            var data: Data
        }

        /// One photo on the screen.
        struct Row: Identifiable {
            var id: Int
            var label: String
            var original: CGImage?
            var cutout: CGImage?
            var record: CutoutBenchRecord?
            var isRunning = false
        }

        static let sizes = [1024, 1536, 2048]

        private(set) var rows: [Row] = []
        private(set) var isLoading = false
        private(set) var isRunning = false
        var maxPixelSize = 1536

        /// Set by the first cutout since launch, so later runs are counted as warm.
        private(set) var hasColdStarted = false

        let device: String
        private let makeService: @Sendable (Int) -> any CutoutService
        private var inputs: [Input] = []
        private var runTask: Task<Void, Never>?

        init(device: String, makeService: @escaping @Sendable (Int) -> any CutoutService) {
            self.device = device
            self.makeService = makeService
        }

        var report: CutoutBenchReport {
            CutoutBenchReport(records: rows.compactMap(\.record), maxPixelSize: maxPixelSize, device: device)
        }

        // MARK: Photos

        /// Shows "Loading photos" while `load` reads them, then measures them.
        func load(_ load: @escaping @Sendable () async -> [Input]) {
            runTask?.cancel()
            isLoading = true
            rows = []
            runTask = Task {
                let inputs = await load()
                guard !Task.isCancelled else { return }
                self.isLoading = false
                await self.measure(inputs)
            }
        }

        /// Measures the same photos again, for example at another working size.
        func runAgain() {
            let inputs = inputs
            runTask?.cancel()
            runTask = Task { await self.measure(inputs) }
        }

        func cancel() {
            runTask?.cancel()
        }

        func mark(_ id: Int, usable: Bool?) {
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[index].record?.usable = usable
        }

        // MARK: Measuring

        func measure(_ inputs: [Input]) async {
            self.inputs = inputs
            isRunning = true
            defer { isRunning = false }
            rows = inputs.indices.map { Row(id: $0 + 1, label: inputs[$0].label) }
            for (index, input) in inputs.enumerated() {
                rows[index].original = await Self.thumbnail(of: input.data)
            }
            let service = makeService(maxPixelSize)
            for (index, input) in inputs.enumerated() {
                guard !Task.isCancelled else { return }
                rows[index].isRunning = true
                let (outcome, cutout) = await measureOne(input.data, with: service)
                rows[index].isRunning = false
                rows[index].record = CutoutBenchRecord(id: index + 1, label: input.label, outcome: outcome)
                rows[index].cutout = cutout
            }
        }

        private func measureOne(_ data: Data, with service: any CutoutService) async -> (
            CutoutBenchRecord.Outcome, CGImage?
        ) {
            let isColdStart = !hasColdStarted
            let baseline = ProcessMemory.footprint()
            let clock = ContinuousClock()
            let (runs, memory) = await MemorySampler.measure { () -> [(Duration, Result<CutoutResult, CutoutError>)] in
                var runs: [(Duration, Result<CutoutResult, CutoutError>)] = []
                for _ in 0..<2 {
                    let start = clock.now
                    let result: Result<CutoutResult, CutoutError>
                    do throws(CutoutError) {
                        result = .success(try await service.cutout(from: data))
                    } catch {
                        result = .failure(error)
                    }
                    runs.append((clock.now - start, result))
                    if case .failure = result { break }
                }
                return runs
            }
            switch (runs.first?.1, runs.last?.1) {
            case (.success, .success(let second)) where runs.count == 2:
                hasColdStarted = true
                let measured = CutoutBenchRecord.Measured(
                    first: runs[0].0, second: runs[1].0, isColdStart: isColdStart, timings: second.timings,
                    pixelWidth: second.pixelWidth, pixelHeight: second.pixelHeight, quality: second.quality,
                    baselineFootprint: baseline, memory: memory)
                return (.measured(measured), await Self.thumbnail(of: second.imageData))
            case (_, .failure(let error)):
                return (.failed(error), nil)
            default:
                return (.failed(.failed), nil)
            }
        }

        /// A small copy for the list, made off the main actor, so the screen never holds
        /// full-size photos as bitmaps.
        @concurrent
        nonisolated static func thumbnail(of data: Data, maxPixelSize: Int = 300) async -> CGImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                ] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        }
    }
#endif
