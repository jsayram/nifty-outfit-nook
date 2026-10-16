#if DEBUG
    import Fixtures
    import Foundation
    import Models
    import Testing

    @testable import Features

    /// The cutout benchmark's arithmetic, report and runs, with the stand-in service (Vision
    /// can't run on the simulator).
    @MainActor
    struct CutoutBenchTests {
        // MARK: Percentiles

        @Test func percentilesUseTheNearestRank() {
            let times = (1...10).map { Duration.milliseconds($0 * 100) }.shuffled()
            #expect(CutoutBenchReport.percentile(0.5, of: times) == .milliseconds(500))
            #expect(CutoutBenchReport.percentile(0.9, of: times) == .milliseconds(900))
            #expect(CutoutBenchReport.percentile(1, of: times) == .seconds(1))
            #expect(CutoutBenchReport.percentile(0.9, of: [.milliseconds(42)]) == .milliseconds(42))
            #expect(CutoutBenchReport.percentile(0.5, of: []) == nil)
        }

        @Test func formatting() {
            #expect(CutoutBenchReport.milliseconds(.microseconds(1_499)) == 1)
            #expect(CutoutBenchReport.mb(300 * 1_048_576) == "300 MB")
            #expect(CutoutBenchReport.percent(0.705) == "71%")
            #expect(CutoutBenchReport.edges([]) == "none")
            #expect(CutoutBenchReport.edges([.bottom, .top]) == "top+bottom")
        }

        // MARK: Report

        private func measured(
            first: Int, second: Int, cold: Bool = false, peakMB: UInt64 = 120,
            quality: CutoutQuality = StandInCutoutService.cleanQuality
        ) -> CutoutBenchRecord.Outcome {
            .measured(
                CutoutBenchRecord.Measured(
                    first: .milliseconds(first), second: .milliseconds(second), isColdStart: cold,
                    timings: CutoutTimings(lift: .milliseconds(second)), pixelWidth: 600, pixelHeight: 800,
                    quality: quality, baselineFootprint: 80 * 1_048_576,
                    memory: .init(peakFootprint: peakMB * 1_048_576, leastAvailable: 1_500 * 1_048_576)))
        }

        private var messy: CutoutQuality {
            CutoutQuality(
                instanceCount: 1, coverage: 0.5, largestInstanceShare: 1, touchedEdges: [.left, .right],
                softEdgeRatio: 0.1, subjectBounds: .whole)
        }

        private func report(_ records: [CutoutBenchRecord]) -> CutoutBenchReport {
            CutoutBenchReport(records: records, maxPixelSize: 1536, device: "iPhone13,2, iOS 26.1")
        }

        @Test func theColdStartIsKeptOutOfTheWarmTimes() {
            let report = report([
                CutoutBenchRecord(id: 1, label: "Photo 1", outcome: measured(first: 3_000, second: 400, cold: true)),
                CutoutBenchRecord(id: 2, label: "Photo 2", outcome: measured(first: 500, second: 450)),
            ])
            #expect(report.coldStart == .seconds(3))
            #expect(report.warmTimes.sorted() == [.milliseconds(400), .milliseconds(450), .milliseconds(500)])
            #expect(report.medianWarm == .milliseconds(450))
        }

        @Test func everyCheckPassesOnAGoodRun() {
            let report = report([
                CutoutBenchRecord(
                    id: 1, label: "Photo 1", outcome: measured(first: 2_000, second: 600, cold: true), usable: true),
                CutoutBenchRecord(id: 2, label: "Photo 2", outcome: measured(first: 700, second: 650), usable: true),
                CutoutBenchRecord(id: 3, label: "Photo 3", outcome: measured(first: 800, second: 750), usable: true),
                CutoutBenchRecord(
                    id: 4, label: "Photo 4", outcome: measured(first: 900, second: 850, quality: messy), usable: false),
            ])
            #expect(report.checks.allSatisfy { $0.passes == true }, "\(report.checks)")
            #expect(report.usableShare == 0.75)
            #expect(report.suggestedStickers == 3)
            #expect(report.agreement.agreeing == 4 && report.agreement.of == 4)
        }

        @Test func slowHeavyOrUnusableRunsFail() {
            let report = report([
                CutoutBenchRecord(
                    id: 1, label: "Photo 1", outcome: measured(first: 9_000, second: 2_500, cold: true, peakMB: 400),
                    usable: false),
                CutoutBenchRecord(id: 2, label: "Photo 2", outcome: .failed(.noSubject)),
            ])
            #expect(report.checks.allSatisfy { $0.passes == false }, "\(report.checks)")
            // The photo with no subject counts as not usable without a mark.
            #expect(report.marked.count == 2)
            #expect(report.usableShare == 0)
        }

        @Test func aDeviceThatCannotLiftSaysNothingAboutThePhotos() {
            let report = report([
                CutoutBenchRecord(id: 1, label: "Photo 1", outcome: .failed(.unsupported)),
                CutoutBenchRecord(id: 2, label: "Photo 2", outcome: .failed(.cancelled)),
            ])
            #expect(report.usableShare == nil)
            #expect(report.checks.allSatisfy { $0.passes == nil })
        }

        @Test func theExportHasTheNumbersAndOneRowPerPhoto() throws {
            let report = report([
                CutoutBenchRecord(
                    id: 1, label: "Photo 1", outcome: measured(first: 2_000, second: 600, cold: true), usable: true),
                CutoutBenchRecord(id: 2, label: "Photo 2", outcome: measured(first: 700, second: 650, quality: messy)),
                CutoutBenchRecord(id: 3, label: "Photo 3", outcome: .failed(.noSubject)),
            ])
            let text = report.text(date: Date(timeIntervalSince1970: 1_791_979_200))
            #expect(text.contains("Device: iPhone13,2, iOS 26.1, Debug build"))
            #expect(text.contains("Date: 2026-10-14"))
            #expect(text.contains("Cold start: 2,000 ms"))
            #expect(text.contains("Warm time: median 650 ms, p90 700 ms (3 runs)"))
            #expect(text.contains("[pass] Median warm time at most 1,000 ms: 650 ms"))
            let lines = text.split(separator: "\n")
            let header = try #require(lines.firstIndex { $0.hasPrefix("#\tphoto") })
            let rows = lines.dropFirst(header + 1)
            #expect(rows.count == 3)
            for row in rows {
                #expect(row.split(separator: "\t", omittingEmptySubsequences: false).count == 17, "\(row)")
            }
            #expect(rows.first?.contains("2000 (cold)") == true)
            #expect(rows.dropFirst().first?.contains("tile (runsOffThePhoto)") == true)
            #expect(rows.last?.contains("failed: noSubject") == true)
        }

        // MARK: Runs

        private func photos(_ count: Int) -> [CutoutBenchModel.Input] {
            (1...count).map {
                CutoutBenchModel.Input(
                    label: "Sample \($0)", data: SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 300, height: 400))
            }
        }

        @Test(.heavyMainActorWork) func eachPhotoIsMeasuredTwiceAndOnlyTheFirstIsCold() async throws {
            let model = CutoutBenchModel(device: "test") { _ in StandInCutoutService() }
            await model.measure(photos(3))
            #expect(model.rows.count == 3)
            #expect(!model.isRunning)
            let records = model.rows.compactMap(\.record)
            let measured = records.compactMap(\.measured)
            #expect(measured.count == 3)
            #expect(measured.map(\.isColdStart) == [true, false, false])
            #expect(measured.allSatisfy { $0.memory.peakFootprint > 0 && $0.pixelWidth == 300 })
            #expect(model.rows.allSatisfy { $0.original != nil && $0.cutout != nil })

            // A second run in the same launch has no cold start.
            await model.measure(photos(2))
            #expect(model.rows.compactMap(\.record?.measured).allSatisfy { !$0.isColdStart })
            #expect(model.report.coldStart == nil)
        }

        @Test(.heavyMainActorWork) func theWorkingSizeReachesTheService() async {
            let sizes = SizeLog()
            let model = CutoutBenchModel(device: "test") { size in
                sizes.add(size)
                return StandInCutoutService()
            }
            model.maxPixelSize = 2048
            await model.measure(photos(1))
            #expect(sizes.values == [2048])
        }

        @Test func failuresAreRecordedAndNotRetried() async {
            let model = CutoutBenchModel(device: "test") { _ in StandInCutoutService(outcome: .fails(.noSubject)) }
            await model.measure(photos(2))
            #expect(model.rows.map(\.record?.outcome) == [.failed(.noSubject), .failed(.noSubject)])
            #expect(!model.hasColdStarted)
        }

        @Test func marksCanBeSetAndCleared() async {
            let model = CutoutBenchModel(device: "test") { _ in StandInCutoutService() }
            await model.measure(photos(2))
            model.mark(1, usable: true)
            model.mark(2, usable: false)
            #expect(model.report.usableShare == 0.5)
            model.mark(2, usable: nil)
            #expect(model.report.usableShare == 1)
            model.mark(99, usable: true)
            #expect(model.report.marked.count == 1)
        }

        // MARK: Memory

        @Test func memoryIsReadable() async {
            #expect(ProcessMemory.footprint() > 0)
            #expect(ProcessMemory.lifetimePeak() >= ProcessMemory.footprint() / 2)
            let (value, reading) = await MemorySampler.measure { () -> Int in
                let bytes = [UInt8](repeating: 1, count: 8 * 1_048_576)
                try? await Task.sleep(for: .milliseconds(30))
                return bytes.count
            }
            #expect(value == 8 * 1_048_576)
            #expect(reading.peakFootprint > 0)
        }
    }

    /// Records the sizes the benchmark asked for, from any thread.
    private final class SizeLog: @unchecked Sendable {
        private let lock = NSLock()
        private var sizes: [Int] = []
        var values: [Int] { lock.withLock { sizes } }
        func add(_ size: Int) { lock.withLock { sizes.append(size) } }
    }
#endif
