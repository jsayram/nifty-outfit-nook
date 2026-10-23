import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// The iCloud screen's model and rows (Phase 21b) against a scripted service: hidden without
/// sync, asks before turning on, says why it couldn't, and passes her answers on.
@MainActor
struct ICloudModelTests {
    actor ScriptedICloud: ICloudSyncService {
        var current = ICloudSyncStatus()
        var turnOnResult = ICloudTurnOnResult.on
        private(set) var calls: [String] = []

        nonisolated var mayHaveCopy: Bool { true }
        func deleteCopy() async -> DeletionOutcome { .deleted }
        func status() async -> ICloudSyncStatus { current }
        func setTurnOnResult(_ result: ICloudTurnOnResult) { turnOnResult = result }

        func turnOn() async -> ICloudTurnOnResult {
            calls.append("turnOn")
            if turnOnResult == .on { current.state = .on }
            return turnOnResult
        }

        func turnOff(deletingCopy: Bool) async -> DeletionOutcome {
            calls.append("turnOff(\(deletingCopy))")
            current.state = .off
            return .deleted
        }

        func answer(_ choice: ICloudChoice) async { calls.append("answer(\(choice.rawValue))") }
        func syncNow() async { calls.append("syncNow") }
    }

    @Test("The row shows only in a build with sync, before Backups")
    func rows() {
        #expect(!ProfileDestination.helpAndPrivacy(showsBackups: true).contains(.iCloud))
        #expect(
            ProfileDestination.helpAndPrivacy(showsBackups: true, showsICloud: true) == [
                .accessibility, .help, .feedback, .privacy, .iCloud, .backups, .deleteData,
            ])
        // No build has sync until Jose turns it on: the services start without it.
        #expect(FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar).iCloud == nil)
    }

    @Test("Turning on asks first; a refusal says why")
    func turnOn() async {
        let service = ScriptedICloud()
        let model = ICloudModel()
        await model.load(service)
        #expect(model.status?.state == .off)
        model.set(true)
        #expect(model.isAskingTurnOn)
        #expect(await service.calls.isEmpty)

        await service.setTurnOnResult(.noAccount)
        await model.turnOn(service)
        #expect(model.problem == ICloudText.turnOnProblem(.noAccount))
        #expect(model.status?.state == .off)

        await service.setTurnOnResult(.on)
        await model.turnOn(service)
        #expect(model.problem == nil)
        #expect(model.status?.state == .on)
    }

    @Test("Turning off asks how, and her answers and Try again reach the service")
    func turnOffAndAnswers() async {
        let service = ScriptedICloud()
        let model = ICloudModel()
        model.set(false)
        #expect(model.isAskingTurnOff)
        await model.turnOff(service, deletingCopy: true)
        await model.answer(.copyToThisAccount, service)
        await model.tryAgain(service)
        #expect(await service.calls == ["turnOff(true)", "answer(copyToThisAccount)", "syncNow"])
    }

    @Test("Never says everything is in iCloud while anything waits")
    func upToDate() {
        #expect(ICloudSyncStatus(state: .on).isUpToDate)
        #expect(!ICloudSyncStatus(state: .on, waitingPhotos: 1).isUpToDate)
        #expect(!ICloudSyncStatus(state: .on, problem: .offline).isUpToDate)
        #expect(!ICloudSyncStatus(state: .paused(.signedOut)).isUpToDate)
        // Every pause has words, and the choices it offers have words too.
        for pause in ICloudPause.allCases {
            #expect(!ICloudText.pause(pause).isEmpty)
            for choice in pause.choices { #expect(!ICloudText.choice(choice, in: pause).isEmpty) }
        }
    }
}
