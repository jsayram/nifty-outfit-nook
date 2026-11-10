import Foundation
import Models
import Testing

/// N4: the `-hold`, `-fail` and `-faults-wait` launch flags behind the capture hooks.
struct DebugFaultsTests {
    @Test func readsHoldsAndFailsWithTheirVariants() {
        let faults = DebugFaults(arguments: [
            "App", "-hold", "store-load,weather", "-fail", "send=offline, closet-save", "-fixtures", "demo",
        ])
        #expect(faults.holds == ["store-load", "weather"])
        #expect(faults.fails == ["send": "offline", "closet-save": ""])
        #expect(!faults.waitsForSignal)
    }

    @Test func readsEachFlagMoreThanOnceAndTheWaitFlag() {
        let faults = DebugFaults(arguments: ["App", "-fail", "export", "-fail", "check=damaged", "-faults-wait"])
        #expect(faults.fails == ["export": "", "check": "damaged"])
        #expect(faults.holds.isEmpty)
        #expect(faults.waitsForSignal)
    }

    @Test func ignoresAMissingValueAndEmptyScopes() {
        #expect(DebugFaults(arguments: ["App", "-hold"]).isEmpty)
        #expect(DebugFaults(arguments: ["App", "-fail", ",,=x"]).isEmpty)
        #expect(DebugFaults(arguments: ["App"]) == .none)
    }

    @Test func aStoreCallAnswersToItsMethodItsStoreAndItsKind() {
        #expect(
            DebugFaults.storeScopes(store: "closet", method: "garment(_:)")
                == ["closet.garment", "closet-load", "store-load", "closet"])
        #expect(
            DebugFaults.storeScopes(store: "profile", method: "update(_:)")
                == ["profile.update", "profile-save", "store-save", "profile"])
    }

    @Test func aFailureMatchesTheFirstScopeItNamesAndAll() async {
        let faults = DebugFaults(fails: ["closet-load": "", "send": "offline"])
        #expect(
            await faults.fault(for: ["closet.garments", "closet-load"])
                == .fail(.init(scope: "closet-load", variant: nil)))
        #expect(await faults.fault(for: ["send"]) == .fail(.init(scope: "send", variant: "offline")))
        #expect(await faults.fault(for: ["looks-load"]) == nil)
        #expect(await DebugFaults(fails: ["all": ""]).fault(for: ["weather"]) != nil)
    }

    @Test func aHoldWaitsUntilItsTaskIsCancelled() async {
        let faults = DebugFaults(holds: ["weather"], fails: ["weather": ""])
        let held = Task { await faults.fault(for: ["weather"]) }
        try? await Task.sleep(for: .milliseconds(200))
        held.cancel()
        #expect(await held.value == .cancelled)
    }
}

/// Arming changes state for the whole process, so these run one at a time.
@Suite(.serialized)
struct DebugFaultsArmingTests {
    @Test func waitsForTheSignalBeforeFailing() async {
        DebugFaults.disarm()
        defer { DebugFaults.disarm() }
        let faults = DebugFaults(fails: ["looks-load": ""], waitsForSignal: true)
        #expect(await faults.fault(for: ["looks-load"]) == nil)
        DebugFaults.arm()
        #expect(await faults.fault(for: ["looks-load"]) != nil)
    }
}
