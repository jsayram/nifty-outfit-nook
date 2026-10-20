import Foundation
import Models
import SwiftData

/// Moves the Stage A `UserDefaults` suite into the real store, once (Phase 21a).
///
/// Lily's TestFlight builds kept that onboarding was done, the starting closet, the tours seen,
/// the tips switch, the name on her sign and three Style Me settings in the app's own suite
/// (`AppStateDefaults`). The first launch of a 21a build writes each of them into the store, with
/// the same careful reading as before (a damaged value reads as not set), then records that the
/// import happened, then empties the suite. A launch killed half way just does it again: the
/// suite is still there, and writing the same values twice changes nothing. Later launches see
/// the record and only make sure the suite is empty.
///
/// Values already in the store win: the import only fills what the store doesn't have.
public enum AppStateDefaultsImport {
    /// What the import did, for the tests.
    public enum Outcome: Equatable, Sendable {
        /// The suite's values were written into the store.
        case imported
        /// There was nothing to move.
        case nothingToImport
        /// An earlier launch already did it.
        case alreadyDone
        /// The store couldn't be written. The suite is left as it was, for the next launch.
        case failed
    }

    @discardableResult
    public static func run(
        suiteName: String = AppStateDefaults.suiteName, into container: ModelContainer, now: Date = .now
    ) -> Outcome {
        let defaults = AppStateDefaults.suite(named: suiteName)
        let context = ModelContext(container)
        let marker = RecordTable<StoredDefaultsImport>(kind: .defaultsImport)
        do throws(StoreError) {
            if try marker.value(RecordKind.singleKey, in: context) != nil {
                empty(defaults, suiteName: suiteName)
                return .alreadyDone
            }
            let hasValues = AppStateDefaults.Key.all.contains { defaults.object(forKey: $0) != nil }
            if hasValues {
                try importValues(from: defaults, into: context)
            }
            try marker.write([RecordKind.singleKey: StoredDefaultsImport(importedAt: now)], in: context)
            empty(defaults, suiteName: suiteName)
            return hasValues ? .imported : .nothingToImport
        } catch {
            return .failed
        }
    }

    private static func importValues(from defaults: UserDefaults, into context: ModelContext) throws(StoreError) {
        let onboarding = RecordTable<StoredOnboarding>(kind: .onboarding)
        let state = AppStateDefaults.onboardingState(in: defaults)
        if state.isCompleted, try onboarding.value(RecordKind.singleKey, in: context) == nil {
            try onboarding.write(
                [RecordKind.singleKey: StoredOnboarding(isCompleted: true, startingCloset: state.startingCloset)],
                in: context)
        }

        let tours = RecordTable<StoredTours>(kind: .tours)
        if try tours.value(RecordKind.singleKey, in: context) == nil {
            let seen = AppStateDefaults.seenVersions(in: defaults)
            try tours.write(
                [
                    RecordKind.singleKey: StoredTours(
                        seenVersions: Dictionary(uniqueKeysWithValues: seen.map { ($0.key.rawValue, $0.value) }),
                        showsTipsOnNewScreens: AppStateDefaults.showsTips(in: defaults))
                ], in: context)
        }

        let profiles = RecordTable<Profile>(kind: .profile)
        let kept = AppStateDefaults.keptProfileSettings(in: defaults)
        if kept != .none, try profiles.value(RecordKind.singleKey, in: context) == nil {
            var profile = Profile()
            kept.apply(to: &profile)
            try profiles.write([RecordKind.singleKey: try StoreValidation.profile(profile)], in: context)
        }
    }

    private static func empty(_ defaults: UserDefaults, suiteName: String) {
        for key in AppStateDefaults.Key.all {
            defaults.removeObject(forKey: key)
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}
