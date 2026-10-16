import Foundation
import Models
import Testing

/// What every `ProfileStore` does. See `StoreContract.swift` for how to run it.
public struct ProfileStoreContract: Sendable {
    /// Makes a store holding this profile.
    public typealias Factory = @Sendable (Profile) async throws -> any ProfileStore

    public enum Check: String, CaseIterable, Sendable {
        case readsWhatWasSaved
        case saveTrimsAndChecksTheSignName
        case saveChecksFitPieces
        case saveRefusesMeasurementsOutOfRange
        case updateChangesAndChecks
        case updatesMadeAtOnceAllLand
        case eraseAllLeavesAFreshProfile
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    public func run(_ check: Check) async throws {
        let start = Profile(signName: "Lily", usualFit: .comfortable)
        let store = try await make(start)

        switch check {
        case .readsWhatWasSaved:
            #expect(try await store.profile() == start)
            var changed = start
            changed.preferences.tracksLaundry = true
            changed.measurements.height = Length(59, .inches)
            try await store.save(changed)
            #expect(try await store.profile() == changed)

        case .saveTrimsAndChecksTheSignName:
            var profile = start
            profile.signName = "  Lily  "
            try await store.save(profile)
            #expect(try await store.profile().signName == "Lily")
            // Empty is allowed: the sign shows a neutral fallback.
            profile.signName = ""
            try await store.save(profile)
            #expect(try await store.profile().signName == "")
            profile.signName = String(repeating: "L", count: NameRules.signNameMaximum + 1)
            #expect(
                await storeError { try await store.save(profile) }
                    == .invalidName(.tooLong(maximum: NameRules.signNameMaximum)))
            #expect(try await store.profile().signName == "")

        case .saveChecksFitPieces:
            var profile = start
            profile.fitPieces = [FitPiece(id: "f1", brand: " Old Navy ", category: .bottom, sizeLabel: "0 Petite")]
            try await store.save(profile)
            #expect(try await store.profile().fitPieces.first?.brand == "Old Navy")
            profile.fitPieces = [FitPiece(id: "f1", brand: "", category: .bottom, sizeLabel: "0")]
            #expect(await storeError { try await store.save(profile) } == .invalidName(.empty))

        case .saveRefusesMeasurementsOutOfRange:
            var profile = start
            profile.measurements.height = Length(400, .inches)
            let error = await storeError { try await store.save(profile) }
            #expect(error == .invalidMeasurements(MeasurementRules.problems(in: profile.measurements)))
            #expect(try await store.profile() == start)

        case .updateChangesAndChecks:
            let saved = try await store.update { $0.preferences.tracksLaundry = true }
            #expect(saved.preferences.tracksLaundry)
            #expect(try await store.profile() == saved)
            #expect(
                await storeError { try await store.update { $0.measurements.waist = Length(-1, .inches) } }
                    == .invalidMeasurements(
                        MeasurementRules.problems(in: BodyMeasurements(waist: Length(-1, .inches)))))
            #expect(try await store.profile() == saved)

        case .updatesMadeAtOnceAllLand:
            // Each change reads, changes and writes in one step, so none is lost.
            await withTaskGroup(of: Void.self) { group in
                for color in ColorName.allCases {
                    group.addTask { _ = try? await store.update { $0.likedColors.append(color) } }
                }
            }
            #expect(Set(try await store.profile().likedColors) == Set(ColorName.allCases))

        case .eraseAllLeavesAFreshProfile:
            try await store.eraseAll()
            #expect(try await store.profile() == Profile())
            try await store.eraseAll()
        }
    }
}
