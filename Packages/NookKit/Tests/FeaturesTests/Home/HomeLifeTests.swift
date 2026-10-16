import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// The window follows the weather (RD-01.4).
struct RoomWindowTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    private func weather(_ condition: WeatherCondition, night: Bool = false) -> WeatherSnapshot {
        WeatherSnapshot(condition: condition, temperatureCelsius: 15, isNight: night, observedAt: now)
    }

    @Test func eachConditionHasItsWindow() {
        #expect(RoomWindow(weather: weather(.sun)) == .sun)
        #expect(RoomWindow(weather: weather(.cloudy)) == .cloudy)
        #expect(RoomWindow(weather: weather(.rain)) == .rain)
        #expect(RoomWindow(weather: weather(.snow)) == .snow)
    }

    /// After dark it's the night window, whatever the weather, as in the mockups.
    @Test(arguments: WeatherCondition.allCases)
    func nightWinsOverTheCondition(_ condition: WeatherCondition) {
        #expect(RoomWindow(weather: weather(condition, night: true)) == .night)
    }

    /// Loading, or weather that can't be read: a plain window that doesn't guess.
    @Test func noWeatherIsAPlainWindow() {
        #expect(RoomWindow(weather: nil) == .plain)
        #expect(RoomWindow.plain.accessibilityLabel == nil)
    }

    @Test func eachWindowHasItsOwnDrawing() {
        #expect(Set(RoomWindow.allCases.map(\.art)).count == RoomWindow.allCases.count)
    }

    @Test func onlyNightLightsTheLamp() {
        #expect(RoomWindow.allCases.filter(\.lightsTheLamp) == [.night])
    }

    /// VoiceOver hears the weather the window shows.
    @Test func windowLabelsNameTheWeather() {
        #expect(RoomWindow.rain.accessibilityLabel == "Window: Rain")
        #expect(RoomWindow.sun.accessibilityLabel == "Window: Sunny")
        #expect(RoomWindow.night.accessibilityLabel == "Window: Night")
        for window in RoomWindow.allCases where window != .plain {
            #expect(window.accessibilityLabel != nil)
        }
    }
}

/// The hamper's drawing follows laundry tracking and how much there is to wash (RD-11).
struct HamperLookTests {
    @Test func eachHamperStateHasItsDrawing() {
        #expect(HamperLook(hamper: .off) == .faded)
        #expect(HamperLook(hamper: .allClean) == .empty)
        #expect(HamperLook(hamper: .toWash(1)) == .some)
        #expect(HamperLook(hamper: .toWash(HamperLook.fullFrom - 1)) == .some)
        #expect(HamperLook(hamper: .toWash(HamperLook.fullFrom)) == .full)
        #expect(HamperLook(hamper: .toWash(40)) == .full)
    }

    /// While the closet loads, the hamper is plain, not faded: it doesn't claim tracking is off.
    @Test func loadingIsPlainAndEmpty() {
        #expect(HamperLook(hamper: nil) == .empty)
    }

    @Test func drawingsAndPlacement() {
        #expect(Set(HamperLook.allCases.map(\.art)).count == HamperLook.allCases.count)
        // The full hamper is taller, but its basket sits where the others' does.
        let full = HamperLook.full.stageRect
        let empty = HamperLook.empty.stageRect
        #expect(full.maxY == empty.maxY)
        #expect(full.minX == empty.minX && full.width == empty.width)
        #expect(full.height > empty.height)
    }
}

/// Maya's z's (RD-12).
struct SleepyZTests {
    @Test func thereAreThreeZs() {
        #expect(SleepyZ.all.count == 3)
        #expect(Set(SleepyZ.all.map(\.id)).count == 3)
    }

    /// They drift a little and come back: at most 1.5 units across, 3 up and 20% fainter.
    @Test func driftIsGentleAndReturns() {
        for letter in SleepyZ.all {
            for step in 0...70 {
                let drift = letter.drift(at: Double(step) / 10)
                #expect((0...1.5).contains(drift.x))
                #expect((-3...0).contains(drift.y))
                #expect((0.8...1).contains(drift.fade))
            }
            let start = letter.drift(at: 0)
            let later = letter.drift(at: SleepyZ.period)
            #expect(abs(start.y - later.y) < 0.0001)
        }
    }

    /// Each z is a little behind the one below it, so they rise one after another.
    @Test func zsDoNotMoveTogether() {
        let drifts = SleepyZ.all.map { $0.drift(at: 1) }
        #expect(Set(drifts.map { ($0.y * 1000).rounded() }).count == 3)
    }

    /// Under Reduce Motion they rest where the mockup puts them, and still show.
    @Test func restingZsShow() {
        #expect(SleepyZ.Drift.rest == SleepyZ.Drift(x: 0, y: 0, fade: 1))
        #expect(SleepyZ.all.allSatisfy { $0.opacity > 0.3 })
    }
}

@MainActor
struct HomeLifeModelTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func theWindowGetsTheWeather() async {
        let model = HomeModel()
        await model.load(from: FixtureServices.make(set: .demo, weather: .snow, now: now))
        #expect(model.content.window == .snow)
        #expect(model.phase == .loaded)
    }

    /// LR-04.3: weather that can't be read is a plain window, not a failed room.
    @Test func unreadableWeatherIsNotAFailure() async {
        let model = HomeModel()
        await model.load(from: FixtureServices.make(set: .demo, weather: .unavailable, now: now))
        #expect(model.content.window == .plain)
        #expect(model.phase == .loaded)

        let offline = HomeModel()
        await offline.load(from: FixtureServices.make(set: .demo, behavior: .offline, now: now))
        #expect(offline.content.window == .plain)
        #expect(offline.phase == .loaded)
    }

    @Test(arguments: [
        (FixtureLaundryState.off, HamperLook.faded), (.clean, .empty), (.some, .some), (.full, .full),
    ])
    func eachLaundryStateHasItsHamper(_ laundry: FixtureLaundryState, look: HamperLook) async {
        let model = HomeModel()
        await model.load(from: FixtureServices.make(set: .demo, laundry: laundry, now: now))
        #expect(HamperLook(hamper: model.content.hamper) == look)
    }

    /// The demo closet has two pieces marked dirty from before; the sheet says they're kept.
    @Test func dirtyMarksAreCountedWhileTrackingIsOff() async {
        let model = HomeModel()
        await model.load(from: FixtureServices.make(set: .demo, now: now))
        #expect(model.content.hamper == .off)
        #expect(model.keptDirtyCount == 2)
    }

    /// RD-11.4: Turn on saves the setting and the hamper changes without a relaunch.
    @Test func turningTrackingOnUpdatesTheHamper() async throws {
        let services = FixtureServices.make(set: .demo, now: now)
        let model = HomeModel()
        await model.load(from: services)
        #expect(await model.turnOnLaundryTracking(using: services))
        #expect(model.content.hamper == .toWash(2))
        #expect(try await services.profile.profile().preferences.tracksLaundry)
    }

    @Test func turningOnFailsHonestly() async {
        let model = HomeModel()
        #expect(await model.turnOnLaundryTracking(using: .unavailable) == false)
        let failing = FixtureServices.make(set: .demo, behavior: .storesFail, now: now)
        #expect(await model.turnOnLaundryTracking(using: failing) == false)
    }
}
