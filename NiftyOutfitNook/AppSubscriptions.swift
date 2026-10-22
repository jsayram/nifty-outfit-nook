import Fixtures
import Foundation
import Models
import Networking
import Services

/// The styling subscription (Phase 30a): one StoreKit service for the life of the app, with its
/// `Transaction.updates` listener started at launch, and the hint paid requests carry kept current.
///
/// Debug builds take `-subscription none|trial|active|grace|retry|expired|revoked|used-trial|
/// complimentary`, a scripted subscription (and scripted picture packs) for UI tests and
/// screenshots that never touches StoreKit. Running from
/// Xcode uses `NiftyOutfitNookTests/NiftyOutfitNook.storekit` (the scheme's StoreKit
/// configuration), so purchases there are local test purchases.
enum AppSubscriptions {
    static let service: any SubscriptionService = {
        #if DEBUG
            if let name = DebugLaunchArgument.value(after: "-subscription", in: ProcessInfo.processInfo.arguments) {
                return ScriptedSubscriptionService.debug(name, now: Date())
            }
        #endif
        // 30c: the server takes the subscription's and the unlock's signed transactions. Not while
        // the hosted unit tests run inside the app: they drive StoreKit themselves (as for packs).
        let hostedTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let storeKit = StoreKitSubscriptionService(
            cache: DefaultsSubscriptionStatusCache(), claimer: hostedTests ? nil : AppGateway.stylingAccess)
        // Before anything reads the status, so no transaction that arrives at launch is missed. Not
        // while the hosted unit tests run inside the app: a second `Transaction.updates` listener
        // here takes updates the tests' own service is waiting for, and which of the two hears a
        // purchase varies from run to run. The tests start their own where they need one.
        if !hostedTests { storeKit.start() }
        return storeKit
    }()

    /// 30b: picture packs. StoreKit's transaction listener starts now, at launch, so a pack paid
    /// for but not yet credited (the app closed, or the server couldn't be reached) is claimed
    /// again; the server credits each transaction once.
    static let credits: any CreditsService = {
        #if DEBUG
            if DebugLaunchArgument.value(after: "-subscription", in: ProcessInfo.processInfo.arguments) != nil {
                return ScriptedCreditsService()
            }
        #endif
        let storeKit = StoreKitCreditsService(claimer: AppGateway.credits)
        // The hosted unit tests (NiftyOutfitNookTests) run inside the app and drive StoreKit
        // themselves; a second packs listener here would claim their purchases too.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            storeKit.start()
        }
        return storeKit
    }()

    /// Keeps the hint on paid requests in step with StoreKit for the life of the app. The server
    /// never trusts it: since 30c it decides from Apple's verified records.
    static func follow() async {
        // The hosted unit tests drive StoreKit themselves (see `service` and `credits`).
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let service = service
        let hint = EntitlementHintSource.shared
        // 30b: packs paid for but not credited at the last launch.
        _ = await credits.recoverUnfinished()
        hint.set(await service.cachedStatus())
        hint.set(await service.refresh())
        for await status in await service.statusUpdates() {
            hint.set(status)
        }
    }
}
