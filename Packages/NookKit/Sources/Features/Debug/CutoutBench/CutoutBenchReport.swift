#if DEBUG
    import Foundation
    import Models

    /// The proposed go/no-go limits for cutouts as the main garment look (Phase 8a). Jose decides
    /// at the checkpoint; these make the benchmark say pass or fail against the proposal.
    nonisolated struct CutoutBenchCriteria: Hashable, Sendable {
        /// Half the warm cutouts finish within this.
        var medianWarm: Duration
        /// Nine in ten warm cutouts finish within this.
        var p90Warm: Duration
        /// The first cutout after launch, while Vision loads its model.
        var coldStart: Duration
        /// The app's highest footprint while cutting out.
        var peakFootprint: UInt64
        /// The share of photos marked usable as a sticker.
        var usableShare: Double

        static let proposed = CutoutBenchCriteria(
            medianWarm: .seconds(1),
            p90Warm: .seconds(2),
            coldStart: .seconds(4),
            peakFootprint: 300 * 1_048_576,
            usableShare: 0.7
        )
    }

    /// One photo's benchmark result.
    nonisolated struct CutoutBenchRecord: Hashable, Sendable, Identifiable {
        struct Measured: Hashable, Sendable {
            /// The first cutout of this photo. For the first photo after launch it includes
            /// Vision loading its model.
            var first: Duration
            /// The same photo again, straight after.
            var second: Duration
            /// True for the first cutout since the app started.
            var isColdStart: Bool
            /// The second run's steps.
            var timings: CutoutTimings
            var pixelWidth: Int
            var pixelHeight: Int
            var quality: CutoutQuality
            /// The footprint just before the first run.
            var baselineFootprint: UInt64
            var memory: MemorySampler.Reading
        }

        enum Outcome: Hashable, Sendable {
            case measured(Measured)
            case failed(CutoutError)
        }

        var id: Int
        var label: String
        var outcome: Outcome
        /// Whether the person running the benchmark judged the cutout usable as a sticker.
        var usable: Bool?

        var measured: Measured? {
            if case .measured(let measured) = outcome { measured } else { nil }
        }
    }

    /// The numbers the benchmark reports, worked out from its records.
    nonisolated struct CutoutBenchReport {
        var records: [CutoutBenchRecord]
        var maxPixelSize: Int
        var device: String
        var thresholds = CutoutThresholds.proposed
        var criteria = CutoutBenchCriteria.proposed

        var measured: [CutoutBenchRecord.Measured] { records.compactMap(\.measured) }

        var coldStart: Duration? { measured.first(where: \.isColdStart)?.first }

        /// Every run except the cold start.
        var warmTimes: [Duration] {
            measured.flatMap { $0.isColdStart ? [$0.second] : [$0.first, $0.second] }
        }

        var medianWarm: Duration? { Self.percentile(0.5, of: warmTimes) }
        var p90Warm: Duration? { Self.percentile(0.9, of: warmTimes) }
        var peakFootprint: UInt64? { measured.map(\.memory.peakFootprint).max() }
        var baselineFootprint: UInt64? { measured.map(\.baselineFootprint).min() }
        var leastAvailable: UInt64? { measured.compactMap(\.memory.leastAvailable).min() }

        var suggestedStickers: Int { measured.filter { thresholds.suggestsSticker($0.quality) }.count }

        /// Photos with a mark. A photo with no cutout counts as not usable without a mark,
        /// unless the device couldn't run subject lifting or the run was cancelled: that says
        /// nothing about the photo.
        var marked: [(record: CutoutBenchRecord, usable: Bool)] {
            records.compactMap { record in
                if let usable = record.usable { return (record, usable) }
                switch record.outcome {
                case .measured, .failed(.unsupported), .failed(.cancelled): return nil
                case .failed: return (record, false)
                }
            }
        }

        var usableShare: Double? {
            let marked = marked
            guard !marked.isEmpty else { return nil }
            return Double(marked.filter(\.usable).count) / Double(marked.count)
        }

        /// How often the proposed thresholds agree with the marks, over measured photos with a mark.
        var agreement: (agreeing: Int, of: Int) {
            let pairs = records.compactMap { record -> Bool? in
                guard let usable = record.usable, let measured = record.measured else { return nil }
                return usable == thresholds.suggestsSticker(measured.quality)
            }
            return (pairs.filter { $0 }.count, pairs.count)
        }

        struct Check: Hashable {
            var name: String
            var value: String
            /// `nil` when there isn't enough data yet.
            var passes: Bool?
        }

        var checks: [Check] {
            [
                Check(
                    name: "Median warm time at most \(Self.ms(criteria.medianWarm))",
                    value: medianWarm.map(Self.ms) ?? "no data",
                    passes: medianWarm.map { $0 <= criteria.medianWarm }),
                Check(
                    name: "p90 warm time at most \(Self.ms(criteria.p90Warm))",
                    value: p90Warm.map(Self.ms) ?? "no data",
                    passes: p90Warm.map { $0 <= criteria.p90Warm }),
                Check(
                    name: "Cold start at most \(Self.ms(criteria.coldStart))",
                    value: coldStart.map(Self.ms) ?? "not in this run (relaunch to measure)",
                    passes: coldStart.map { $0 <= criteria.coldStart }),
                Check(
                    name: "Peak footprint at most \(Self.mb(criteria.peakFootprint))",
                    value: peakFootprint.map(Self.mb) ?? "no data",
                    passes: peakFootprint.map { $0 <= criteria.peakFootprint }),
                Check(
                    name: "Usable as a sticker at least \(Self.percent(criteria.usableShare))",
                    value: usableShare.map(Self.percent) ?? "mark each photo",
                    passes: usableShare.map { $0 >= criteria.usableShare }),
            ]
        }

        // MARK: Export

        /// Plain text to paste into the results table in docs/cutout-feasibility.md. Numbers
        /// only: no pictures and no photo names.
        func text(date: Date = .now) -> String {
            var lines: [String] = []
            let failed = records.count - measured.count
            lines.append("Cutout benchmark, Phase 8a")
            lines.append("Device: \(device), Debug build")
            lines.append("Date: \(date.formatted(.iso8601.year().month().day()))")
            lines.append(
                "Working size: \(maxPixelSize) px. Photos: \(records.count) (\(measured.count) cut out, \(failed) failed)"
            )
            lines.append("")
            lines.append("Cold start: \(coldStart.map(Self.ms) ?? "not in this run")")
            lines.append(
                "Warm time: median \(medianWarm.map(Self.ms) ?? "-"), p90 \(p90Warm.map(Self.ms) ?? "-") (\(warmTimes.count) runs)"
            )
            lines.append(
                "Memory: baseline \(baselineFootprint.map(Self.mb) ?? "-"), peak \(peakFootprint.map(Self.mb) ?? "-"), least headroom \(leastAvailable.map(Self.mb) ?? "not reported")"
            )
            lines.append("Suggested stickers: \(suggestedStickers) of \(measured.count)")
            let marked = marked
            lines.append(
                "Marked usable: \(marked.filter(\.usable).count) of \(marked.count)\(usableShare.map { " (\(Self.percent($0)))" } ?? "")"
            )
            lines.append("Suggestion agrees with the mark: \(agreement.agreeing) of \(agreement.of)")
            lines.append("")
            lines.append("Proposed go/no-go:")
            for check in checks {
                let verdict = check.passes.map { $0 ? "pass" : "FAIL" } ?? "n/a"
                lines.append("  [\(verdict)] \(check.name): \(check.value)")
            }
            lines.append("")
            lines.append("Per photo (tab-separated; times in ms, memory in MB):")
            lines.append(
                [
                    "#", "photo", "first", "second", "decode", "lift", "render", "encode", "size", "peak MB",
                    "instances", "coverage", "largest", "edges", "soft", "suggested", "marked",
                ].joined(separator: "\t"))
            for record in records {
                lines.append(row(for: record).joined(separator: "\t"))
            }
            return lines.joined(separator: "\n")
        }

        private func row(for record: CutoutBenchRecord) -> [String] {
            let mark = record.usable.map { $0 ? "usable" : "not usable" } ?? "-"
            guard let measured = record.measured else {
                if case .failed(let error) = record.outcome {
                    return ["\(record.id)", record.label, "failed: \(error)"] + Array(repeating: "", count: 13) + [mark]
                }
                return []
            }
            let quality = measured.quality
            let concerns = thresholds.concerns(with: quality)
            return [
                "\(record.id)", record.label,
                Self.number(measured.first) + (measured.isColdStart ? " (cold)" : ""),
                Self.number(measured.second),
                Self.number(measured.timings.decode), Self.number(measured.timings.lift),
                Self.number(measured.timings.render), Self.number(measured.timings.encode),
                "\(measured.pixelWidth)x\(measured.pixelHeight)",
                "\(measured.memory.peakFootprint / 1_048_576)",
                "\(quality.instanceCount)",
                String(format: "%.3f", quality.coverage),
                String(format: "%.2f", quality.largestInstanceShare),
                Self.edges(quality.touchedEdges),
                String(format: "%.3f", quality.softEdgeRatio),
                concerns.isEmpty ? "sticker" : "tile (\(concerns.map(\.rawValue).joined(separator: ", ")))",
                mark,
            ]
        }

        // MARK: Arithmetic and formatting

        /// The nearest-rank percentile: the smallest value with at least `fraction` of the values
        /// at or below it.
        static func percentile(_ fraction: Double, of values: [Duration]) -> Duration? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let rank = Int((fraction * Double(sorted.count)).rounded(.up))
            return sorted[min(max(rank, 1), sorted.count) - 1]
        }

        static func milliseconds(_ duration: Duration) -> Int {
            Int((duration / .milliseconds(1)).rounded())
        }

        static func number(_ duration: Duration) -> String { "\(milliseconds(duration))" }
        static func ms(_ duration: Duration) -> String { "\(milliseconds(duration).formatted()) ms" }
        static func mb(_ bytes: UInt64) -> String { "\((bytes / 1_048_576).formatted()) MB" }
        static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

        static func edges(_ edges: CutoutEdges) -> String {
            let names: [(CutoutEdges, String)] = [
                (.top, "top"), (.bottom, "bottom"), (.left, "left"), (.right, "right"),
            ]
            let touched = names.filter { edges.contains($0.0) }.map(\.1)
            return touched.isEmpty ? "none" : touched.joined(separator: "+")
        }
    }
#endif
