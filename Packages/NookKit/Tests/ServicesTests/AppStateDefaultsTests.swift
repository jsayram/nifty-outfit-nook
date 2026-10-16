import Foundation
import Models
import Testing

@testable import Services

/// Phase 17: the onboarding state and the tours seen, kept across launches in the app's own
/// `UserDefaults` suite. Each test uses a suite of its own and removes it afterwards, so nothing
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

    // MARK: What's in the file

    /// Only the four flags are written: no name, nothing she typed, no dates and no identifier
    /// (`closet/DATA_MAP.md`, the app state row).
    @Test func onlyTheFlagsAreWritten() async {
        let suite = Suite()
        let onboarding = DefaultsOnboardingStore(suiteName: suite.name)
        let tours = DefaultsTourProgressStore(suiteName: suite.name)
        await onboarding.complete(startingCloset: .sample)
        await tours.record(record(.home, outcome: .controlActivated))
        await tours.setShowsTipsOnNewScreens(true)

        let contents = suite.contents
        #expect(
            Set(contents.keys) == [
                AppStateDefaults.Key.onboardingCompleted, AppStateDefaults.Key.startingCloset,
                AppStateDefaults.Key.showsTips, AppStateDefaults.Key.seenVersions,
            ])
        #expect(contents[AppStateDefaults.Key.onboardingCompleted] as? Bool == true)
        #expect(contents[AppStateDefaults.Key.startingCloset] as? String == "sample")
        #expect(contents[AppStateDefaults.Key.showsTips] as? Bool == true)
        #expect(contents[AppStateDefaults.Key.seenVersions] as? [String: Int] == ["home": 1])
        // Nothing that looks like a date or how the tour ended.
        let text = "\(contents)"
        #expect(!text.contains("controlActivated"))
        #expect(!text.contains("2026"))
    }

    @Test func theAppSuiteIsTheAppsOwn() {
        #expect(AppStateDefaults.suiteName == "com.jsayram.niftyoutfitnook.appstate")
        #expect(AppStateDefaults.suiteName != Bundle.main.bundleIdentifier)
    }
}
