import Foundation
import Models

/// Phase 32a: a closet bigger than the biggest the app should still handle comfortably: 5,000
/// pieces, 2,000 saved looks plus 1,000 Style Me results she kept but didn't save, and 500 try-on
/// pictures. The same data for every scale check, so the numbers compare.
///
/// It grows the generated large closet (`FixtureSet.large`, 2,400 pieces) by copying its pieces
/// under new IDs, so the names, colours, kinds and photos are as varied as the large closet's. A
/// seventh of the pieces gets other names, which search finds them by (Phase 21c). Looks pick three
/// to five pieces each. A fixed seed makes every run the same.
public struct ScaleData: Sendable {
    public var garments: [Garment]
    public var looks: [Look]
    public var pictures: [TryOnPicture]

    public static let garmentCount = 5_000
    public static let savedLookCount = 2_000
    public static let unsavedLookCount = 1_000
    public static let pictureCount = 500

    /// - Parameter seed: the large closet's pieces, which come first and unchanged.
    public static func make(growing seed: [Garment], now: Date, calendar: Calendar = TestTime.calendar) -> ScaleData {
        var random = Generator(seed: 2_026_10_22)
        var garments = seed
        let otherNameWords = ["Date-night", "Weekend", "Cozy", "Lucky", "Favourite", "Work"]
        var index = seed.count
        while garments.count < garmentCount {
            var copy = seed[index % seed.count]
            copy = Garment(
                id: Garment.ID("g-scale-\(index)"), name: copy.name, otherNames: [], category: copy.category,
                subKind: copy.subKind, colors: copy.colors, colorNote: copy.colorNote, fit: copy.fit,
                dressiness: copy.dressiness, warmth: copy.warmth, seasons: copy.seasons, occasions: copy.occasions,
                brand: copy.brand, sizeLabel: copy.sizeLabel, notes: copy.notes, photo: copy.photo,
                cutout: copy.cutout, ownership: copy.ownership, laundry: copy.laundry,
                availability: copy.availability, isArchived: copy.isArchived, deletedAt: copy.deletedAt,
                wornOn: copy.wornOn, addedAt: calendar.date(byAdding: .day, value: -(index % 700), to: now) ?? now)
            if index.isMultiple(of: 7) {
                copy.otherNames = [
                    otherName(for: copy.name, word: otherNameWords[Int(random.next() % UInt64(otherNameWords.count))])
                ]
            }
            garments.append(copy)
            index += 1
        }
        // The seed's own pieces get other names too, at the same rate.
        for position in garments.indices where position < seed.count && position.isMultiple(of: 7) {
            garments[position].otherNames = [
                otherName(
                    for: garments[position].name,
                    word: otherNameWords[Int(random.next() % UInt64(otherNameWords.count))])
            ]
        }
        let owned = garments.filter { $0.ownership == .owned && $0.deletedAt == nil && !$0.isArchived }
        var looks: [Look] = []
        for number in 0..<(savedLookCount + unsavedLookCount) {
            let pieceCount = 3 + Int(random.next() % 3)
            let pieces = (0..<pieceCount).map { slot in
                LookPiece(
                    id: LookPiece.ID("lp-scale-\(number)-\(slot)"),
                    content: .garment(owned[Int(random.next() % UInt64(owned.count))].id))
            }
            let saved = number < savedLookCount
            let made = calendar.date(byAdding: .hour, value: -number * 5, to: now) ?? now
            looks.append(
                Look(
                    id: Look.ID("l-scale-\(number)"), pieces: pieces,
                    name: saved && number.isMultiple(of: 2) ? "Look \(number)" : nil,
                    occasion: Occasion.allCases[number % Occasion.allCases.count], isSaved: saved,
                    savedAt: saved ? made : nil, createdAt: made))
        }
        let pictures = looks.filter(\.isSaved).enumerated().compactMap { position, look -> TryOnPicture? in
            guard position.isMultiple(of: 4), position / 4 < pictureCount else { return nil }
            return TryOnPicture(
                id: TryOnPicture.ID("p-scale-\(position)"), of: look, image: .simulated, createdAt: look.savedDate)
        }
        return ScaleData(garments: garments, looks: looks, pictures: pictures)
    }

    /// "Lucky" and the last two words of the name: short enough for the 40 characters the store
    /// allows, and never the same as the name.
    private static func otherName(for name: String, word: String) -> String {
        let tail = name.split(separator: " ").suffix(2).joined(separator: " ")
        let candidate = "\(word) \(tail)"
        return String(candidate.prefix(40)).trimmingCharacters(in: .whitespaces)
    }

    /// SplitMix64: small, fast and the same everywhere.
    struct Generator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

/// Timing and memory for the scale checks (Phase 32a). Each line starts with "SCALE" so a run's
/// numbers can be pulled out of the log.
public enum ScaleReport {
    /// The fastest, median and slowest of `runs` timings of `work`, in milliseconds, printed and
    /// returned (fastest first in the tuple).
    @discardableResult
    public static func measure(
        _ label: String, runs: Int = 5, _ work: () throws -> Void
    ) rethrows -> (fastest: Double, median: Double, slowest: Double) {
        var times: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let start = clock.now
            try work()
            times.append(milliseconds(clock.now - start))
        }
        return report(label, times)
    }

    @discardableResult
    public static func measure(
        _ label: String, runs: Int = 5, isolation: isolated (any Actor)? = #isolation, _ work: () async throws -> Void
    ) async rethrows -> (fastest: Double, median: Double, slowest: Double) {
        var times: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let start = clock.now
            try await work()
            times.append(milliseconds(clock.now - start))
        }
        return report(label, times)
    }

    private static func report(_ label: String, _ times: [Double]) -> (fastest: Double, median: Double, slowest: Double)
    {
        let sorted = times.sorted()
        let result = (sorted[0], sorted[sorted.count / 2], sorted[sorted.count - 1])
        print(
            "SCALE \(label): fastest \(format(result.0)) ms, median \(format(result.1)) ms, slowest \(format(result.2)) ms (\(times.count) runs)"
        )
        return result
    }

    public static func note(_ line: String) {
        print("SCALE \(line)")
    }

    public static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    private static func format(_ value: Double) -> String {
        fixed(value)
    }

    /// A number with `digits` decimals, for the SCALE lines.
    public static func fixed(_ value: Double, _ digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    /// The app's memory footprint now, in megabytes (what Xcode's memory gauge shows).
    public static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
