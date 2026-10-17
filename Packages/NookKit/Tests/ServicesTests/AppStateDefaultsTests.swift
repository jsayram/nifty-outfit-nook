import Fixtures
import Foundation
import Models
import Testing

@testable import Services

/// Phase 17: the onboarding state and the tours seen, kept across launches in the app's own
/// `UserDefaults` suite. Since the Stage A audit, also the name on the sign and the Style Me
/// settings. Each test uses a suite of its own and removes it afterwards, so nothing
/// touches the app's real suite or another test's.
///
/// "A relaunch" here is a second store made on the same suite, which is what the app does at
/// launch.
struct AppStateDefaultsTests {
    /// A suite of its own for one test, removed when the test ends.
    final class Suite: Sendable {
        let name = "com.jsayram.niftyoutfitnook.tests.\(UUID().uuidString)"

        /// What's in the file, as plain values.
        var contents: [String: Any] {
            UserDefaults(suiteName: name)?.persistentDomain(forName: name) ?? [:]
        }

        func set(_ value: Any, for key: String) {
            UserDefaults(suiteName: name)?.set(value, forKey: key)
        }

        deinit {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
    }

    // MARK: Onboarding

    @Test func onboardingIsKeptAcrossALaunch() async {
        let suite = Suite()
        let store = DefaultsOnboardingStore(suiteName: suite.name)
        #expect(await store.state() == .fresh)
        await store.complete(startingCloset: .empty)

        let relaunched = DefaultsOnboardingStore(suiteName: suite.name)
        #expect(await relaunched.state() == OnboardingState(isCompleted: true, startingCloset: .empty))
    }

    @Test func erasingOnboardingShowsItAgain() async {
        let suite = Suite()
        let store = DefaultsOnboardingStore(suiteName: suite.name)
        await store.complete(startingCloset: .sample)
        await store.eraseAll()
        #expect(await DefaultsOnboardingStore(suiteName: suite.name).state() == .fresh)
        #expect(suite.contents.isEmpty)
    }

    @Test func damagedOnboardingValuesReadSafely() async {
        let suite = Suite()
        // Not a Bool: onboarding shows again rather than being skipped.
        suite.set("yes", for: AppStateDefaults.Key.onboardingCompleted)
        #expect(await DefaultsOnboardingStore(suiteName: suite.name).state() == .fresh)
        // An unknown closet falls back to the sample closet.
        suite.set(true, for: AppStateDefaults.Key.onboardingCompleted)
        suite.set("garage", for: AppStateDefaults.Key.startingCloset)
        #expect(
            await DefaultsOnboardingStore(suiteName: suite.name).state()
                == OnboardingState(isCompleted: true, startingCloset: .sample))
    }

    // MARK: Tours

    private func record(_ tour: TourID, version: Int = 1, outcome: TourOutcome = .skipped) -> TourRecord {
        TourRecord(tour: tour, version: version, outcome: outcome, date: Date(timeIntervalSince1970: 1_791_979_200))
    }

    @Test func aSeenTourStaysSeenAfterALaunch() async {
        let suite = Suite()
        let store = DefaultsTourProgressStore(suiteName: suite.name)
        #expect(await store.progress() == .fresh)
        await store.record(record(.home))
        await store.record(record(.styleMe, outcome: .finished))
        #expect(await store.progress().records.count == 2)

        let relaunched = await DefaultsTourProgressStore(suiteName: suite.name).progress()
        #expect(relaunched.seenVersions == [.home: 1, .styleMe: 1])
        // How and when each ended stays in memory for the session.
        #expect(relaunched.records.isEmpty)
        #expect(!TourRules.startsAutomatically(.home, version: 1, progress: relaunched))
        #expect(!TourRules.startsAutomatically(.styleMe, version: 1, progress: relaunched))
        #expect(TourRules.startsAutomatically(.yourLooks, version: 1, progress: relaunched))
        // A new version of a tour still shows once more.
        #expect(TourRules.startsAutomatically(.home, version: 2, progress: relaunched))
    }

    @Test func theTipsSwitchIsKept() async {
        let suite = Suite()
        let store = DefaultsTourProgressStore(suiteName: suite.name)
        #expect(await store.progress().showsTipsOnNewScreens)
        await store.setShowsTipsOnNewScreens(false)
        #expect(await !DefaultsTourProgressStore(suiteName: suite.name).progress().showsTipsOnNewScreens)
    }

    @Test func resetAllTipsKeepsTheSwitch() async {
        let suite = Suite()
        let store = DefaultsTourProgressStore(suiteName: suite.name)
        await store.record(record(.closet))
        await store.setShowsTipsOnNewScreens(false)
        await store.forgetSeenTours()
        let progress = await DefaultsTourProgressStore(suiteName: suite.name).progress()
        #expect(progress.seenVersions.isEmpty)
        #expect(!progress.showsTipsOnNewScreens)
        #expect(await store.progress().records.isEmpty)
    }

    @Test func erasingToursIsAFreshInstall() async {
        let suite = Suite()
        let store = DefaultsTourProgressStore(suiteName: suite.name)
        await store.record(record(.closet))
        await store.setShowsTipsOnNewScreens(false)
        await store.eraseAll()
        #expect(await store.progress() == .fresh)
        #expect(await DefaultsTourProgressStore(suiteName: suite.name).progress() == .fresh)
        #expect(suite.contents.isEmpty)
    }

    @Test func aLowerVersionNeverReplacesAHigherOne() async {
        let suite = Suite()
        let store = DefaultsTourProgressStore(suiteName: suite.name)
        await store.record(record(.home, version: 3))
        await store.record(record(.home, version: 1))
        #expect(await DefaultsTourProgressStore(suiteName: suite.name).progress().seenVersions == [.home: 3])
    }

    @Test func damagedTourValuesReadSafely() async {
        let suite = Suite()
        suite.set(
            ["home": 1, "notATour": 1, "closet": "two", "fit": 0, "help": 99_999],
            for: AppStateDefaults.Key.seenVersions)
        suite.set("off", for: AppStateDefaults.Key.showsTips)
        let progress = await DefaultsTourProgressStore(suiteName: suite.name).progress()
        // Only known tours with a sensible version count; tips stay on unless she turned them off.
        #expect(progress.seenVersions == [.home: 1])
        #expect(progress.showsTipsOnNewScreens)

        suite.set([1, 2, 3], for: AppStateDefaults.Key.seenVersions)
        #expect(await DefaultsTourProgressStore(suiteName: suite.name).progress().seenVersions.isEmpty)
    }

    // MARK: The name on the sign and the Style Me settings (Stage A audit)

    /// A profile store as the app makes one at launch: the sample's profile (or a fresh one) with
    /// what's kept in `suite` put in.
    private func profileStore(_ suite: Suite, starting profile: Profile = Profile()) -> KeptSettingsProfileStore {
        KeptSettingsProfileStore(profile: profile, keeper: DefaultsProfileSettingsKeeper(suiteName: suite.name)) {
            InMemoryProfileStore(profile: $0)
        }
    }

    @Test func theNameAndSettingsAreKeptAcrossALaunch() async throws {
        let suite = Suite()
        let store = profileStore(suite)
        #expect(try await store.profile() == Profile())
        try await store.update {
            $0.signName = " Lily "
            $0.preferences = Preferences(pieceMode: .onlyMine, repeatWindow: .noLimit, tracksLaundry: true)
            $0.usualFit = .fitted
            $0.measurements.waist = Length(27.5, .inches)
            $0.units = .metric
            $0.remembered.occasion = .concert
        }

        let relaunched = try await profileStore(suite).profile()
        #expect(relaunched.signName == "Lily")
        #expect(
            relaunched.preferences == Preferences(pieceMode: .onlyMine, repeatWindow: .noLimit, tracksLaundry: true))
        // The rest is in memory only: her fit and measurements are Sensitive.
        var expected = Profile()
        expected.signName = "Lily"
        expected.preferences = relaunched.preferences
        #expect(relaunched == expected)
    }

    @Test func aClearedNameStaysCleared() async throws {
        let suite = Suite()
        let store = profileStore(suite)
        try await store.save(Profile(signName: "Lily"))
        try await store.update { $0.signName = "" }
        // The sample's profile is named, but she cleared it.
        #expect(try await profileStore(suite, starting: Profile(signName: "Sample")).profile().signName == "")
    }

    @Test func aRefusedSaveKeepsNothing() async throws {
        let suite = Suite()
        let store = profileStore(suite)
        try await store.update { $0.signName = "Lily" }
        _ = try? await store.update {
            $0.signName = "Ana"
            $0.measurements.height = Length(400, .inches)
        }
        #expect(try await profileStore(suite).profile().signName == "Lily")
    }

    /// Changes made at once can come back in either order; what's kept is always the latest.
    @Test func changesMadeAtOnceKeepTheLatest() async throws {
        let suite = Suite()
        let store = profileStore(suite)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    _ = try? await store.update {
                        $0.signName = "Name \(index)"
                        $0.preferences.tracksLaundry = index.isMultiple(of: 2)
                    }
                }
            }
        }
        let final = try await store.profile()
        let relaunched = try await profileStore(suite).profile()
        #expect(relaunched.signName == final.signName)
        #expect(relaunched.preferences == final.preferences)
    }

    @Test func erasingTheProfileForgetsTheSettings() async throws {
        let suite = Suite()
        let store = profileStore(suite)
        try await store.update {
            $0.signName = "Lily"
            $0.preferences.tracksLaundry = true
        }
        try await store.eraseAll()
        #expect(try await store.profile() == Profile())
        #expect(try await profileStore(suite).profile() == Profile())
        #expect(suite.contents.isEmpty)
    }

    @Test func damagedProfileValuesReadSafely() async throws {
        let suite = Suite()
        suite.set(String(repeating: "L", count: NameRules.signNameMaximum + 1), for: AppStateDefaults.Key.signName)
        suite.set("sometimes", for: AppStateDefaults.Key.pieceMode)
        suite.set(14, for: AppStateDefaults.Key.repeatWindow)
        suite.set("yes", for: AppStateDefaults.Key.tracksLaundry)
        // Each damaged value is left out, so the launch's own values stay.
        let start = Profile(signName: "Sample", preferences: Preferences(repeatWindow: .twoWeeks))
        #expect(try await profileStore(suite, starting: start).profile() == start)
    }

    // MARK: What's in the file

    /// Only the flags, the name and the three settings are written: nothing about her body or
    /// closet, no dates and no identifier (`closet/DATA_MAP.md`).
    @Test func onlyTheFlagsNameAndSettingsAreWritten() async throws {
        let suite = Suite()
        let onboarding = DefaultsOnboardingStore(suiteName: suite.name)
        let tours = DefaultsTourProgressStore(suiteName: suite.name)
        await onboarding.complete(startingCloset: .sample)
        await tours.record(record(.home, outcome: .controlActivated))
        await tours.setShowsTipsOnNewScreens(true)
        try await profileStore(suite).update {
            $0.signName = "Lily"
            $0.usualFit = .relaxed
            $0.measurements.waist = Length(27.5, .inches)
            $0.fitPieces = [FitPiece(id: "f1", brand: "Example Denim Co.", category: .bottom, sizeLabel: "S")]
            $0.likedColors = [.cream]
        }

        let contents = suite.contents
        #expect(
            Set(contents.keys) == [
                AppStateDefaults.Key.onboardingCompleted, AppStateDefaults.Key.startingCloset,
                AppStateDefaults.Key.showsTips, AppStateDefaults.Key.seenVersions,
                AppStateDefaults.Key.signName, AppStateDefaults.Key.pieceMode, AppStateDefaults.Key.repeatWindow,
                AppStateDefaults.Key.tracksLaundry,
            ])
        #expect(contents[AppStateDefaults.Key.onboardingCompleted] as? Bool == true)
        #expect(contents[AppStateDefaults.Key.startingCloset] as? String == "sample")
        #expect(contents[AppStateDefaults.Key.showsTips] as? Bool == true)
        #expect(contents[AppStateDefaults.Key.seenVersions] as? [String: Int] == ["home": 1])
        #expect(contents[AppStateDefaults.Key.signName] as? String == "Lily")
        #expect(contents[AppStateDefaults.Key.pieceMode] as? String == "mineAndOneIdea")
        #expect(contents[AppStateDefaults.Key.repeatWindow] as? String == "oneWeek")
        #expect(contents[AppStateDefaults.Key.tracksLaundry] as? Bool == false)
        // Nothing that looks like a date, how the tour ended, her fit or her closet.
        let text = "\(contents)"
        for word in ["controlActivated", "2026", "relaxed", "27.5", "Denim", "cream"] {
            #expect(!text.contains(word), "\(word) was written")
        }
    }

    @Test func theAppSuiteIsTheAppsOwn() {
        #expect(AppStateDefaults.suiteName == "com.jsayram.niftyoutfitnook.appstate")
        #expect(AppStateDefaults.suiteName != Bundle.main.bundleIdentifier)
    }
}
