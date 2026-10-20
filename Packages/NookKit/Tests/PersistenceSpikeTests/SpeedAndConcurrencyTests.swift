import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

/// Gates 3 and 4 of the spike: the large closet loads off the main actor without a stall, and
/// two actors saving fast at the same time don't crash or lose records (Phase 20a).
@Suite(.serialized)
struct SpeedAndConcurrencyTests {
    @Test func theLargeClosetLoadsOffTheMainActorWithoutAStall() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let garments = FixtureSet.large.data(now: SpikeSeed.epoch, calendar: calendar).garments
        #expect(garments.count == 2_400)
        let location = try SpikeStoreLocation.temporary("speed")
        defer { location.remove() }
        let coordinator = SpikeMigrationCoordinator(location: location)
        try await SwiftDataClosetStore(container: try coordinator.container(), calendar: calendar).insertAll(garments)

        // A fresh container, as after a relaunch, so the first read is cold.
        let reader = SwiftDataClosetStore(container: try coordinator.container(), calendar: calendar)
        let heartbeat = MainActorHeartbeat()
        await heartbeat.start()
        let clock = ContinuousClock()
        let coldStart = clock.now
        let first = try await reader.garments()
        let cold = clock.now - coldStart
        let warm = try await SpeedCheck.fastest { _ = try await reader.garments() }
        let longestGap = await heartbeat.stop()

        print("SPIKE load 2,400 garments: cold \(cold), warm \(warm), longest main-actor gap \(longestGap)")
        #expect(first.count == 2_400)
        #expect(first == garments.sorted { $0.addedAt != $1.addedAt ? $0.addedAt > $1.addedAt : $0.id < $1.id })
        #expect(cold < SpeedCheck.limit(.seconds(2)), "Cold load took \(cold)")
        #expect(warm < SpeedCheck.limit(.seconds(1)), "Warm load took \(warm)")
        // The main actor ticks every 5 ms throughout; the load never runs on it.
        #expect(longestGap < SpeedCheck.limit(.milliseconds(100)), "The main actor stalled for \(longestGap)")
    }

    /// 1,000 new pieces saved one at a time from two actors at once, each with its own context on
    /// the same store, while both also keep changing the same 20 pieces.
    @Test func aThousandRapidSavesFromTwoActorsAllLand() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let location = try SpikeStoreLocation.temporary("rapid")
        defer { location.remove() }
        let coordinator = SpikeMigrationCoordinator(location: location)
        let container = try coordinator.container()
        let shared = (0..<20).map { Garment(id: Garment.ID("shared-\($0)"), name: "Shared \($0)", category: .top, addedAt: SpikeSeed.epoch) }
        let first = SwiftDataClosetStore(container: container, calendar: calendar)
        let second = SwiftDataClosetStore(container: container, calendar: calendar)
        try await first.insertAll(shared)

        let clock = ContinuousClock()
        let start = clock.now
        async let firstFailures = Self.saveMany(prefix: "a", into: first, shared: shared, laundry: .dirty)
        async let secondFailures = Self.saveMany(prefix: "b", into: second, shared: shared, laundry: .clean)
        let failures = await (firstFailures, secondFailures)
        let elapsed = clock.now - start

        let reader = SwiftDataClosetStore(container: try coordinator.container(), calendar: calendar)
        let all = try await reader.garments()
        print(
            "SPIKE 1,000 rapid saves from two actors: \(elapsed), \(failures.0.inserts + failures.1.inserts) failed "
                + "inserts, \(failures.0.updates + failures.1.updates) failed updates of shared pieces")
        #expect(failures.0.inserts + failures.1.inserts == 0)
        #expect(all.count == 1_020)
        #expect(Set(all.map(\.id)).count == 1_020)
        // Every shared piece ends in a state one of the actors wrote, never a mix.
        #expect(all.filter { $0.id.rawValue.hasPrefix("shared-") }.allSatisfy { $0.wornOn.count <= 1 })
    }

    struct Failures {
        var inserts = 0
        var updates = 0
    }

    static func saveMany(prefix: String, into store: SwiftDataClosetStore, shared: [Garment], laundry: LaundryState)
        async -> Failures
    {
        var failures = Failures()
        for index in 0..<500 {
            let garment = Garment(
                id: Garment.ID("\(prefix)-\(index)"), name: "Piece \(prefix) \(index)", category: .bottom,
                addedAt: SpikeSeed.epoch.addingTimeInterval(Double(index)))
            do { try await store.save(garment) } catch { failures.inserts += 1 }
            if index.isMultiple(of: 5) {
                let target = shared[(index / 5) % shared.count].id
                do {
                    try await store.setLaundry(laundry, for: [target])
                    try await store.recordWear(of: [target], on: SpikeSeed.epoch)
                } catch {
                    failures.updates += 1
                }
            }
        }
        return failures
    }
}

/// Ticks on the main actor every 5 ms and keeps the longest gap between ticks.
@MainActor
final class MainActorHeartbeat {
    private var task: Task<Duration, Never>?

    func start() {
        task = Task { @MainActor in
            let clock = ContinuousClock()
            var last = clock.now
            var longest = Duration.zero
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
                let now = clock.now
                longest = max(longest, now - last - .milliseconds(5))
                last = now
            }
            return longest
        }
    }

    func stop() async -> Duration {
        task?.cancel()
        return await task?.value ?? .zero
    }
}
