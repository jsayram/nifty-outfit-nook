import Fixtures
import Foundation
import Models
import Networking
import Services

/// The styling subscription (Phase 30a): one StoreKit service for the life of the app, with its
/// `Transaction.updates` listener started at launch, and the hint paid requests carry kept current.
///
/// Debug builds take `-subscription none|trial|active|grace|retry|expired|revoked|used-trial`,
/// a scripted subscription for UI tests and screenshots that never touches StoreKit. Running from
/// Xcode uses `NiftyOutfitNookTests/NiftyOutfitNook.storekit` (the scheme's StoreKit
/// configuration), so purchases there are local test purchases.
enum AppSubscriptions {
    static let service: any SubscriptionService = {
        #if DEBUG
            if let name = DebugLaunchArgument.value(after: "-subscription", in: ProcessInfo.processInfo.arguments) {
                return ScriptedSubscriptionService.debug(name, now: Date())
            }
        #endif
        let storeKit = StoreKitSubscriptionService(cache: DefaultsSubscriptionStatusCache())
        // Before anything reads the status, so no transaction that arrives at launch is missed.
        storeKit.start()
        return storeKit
    }()

    /// Keeps the hint on paid requests in step with StoreKit for the life of the app. The server
    /// never trusts it (30c).
    static func follow() async {
        let service = service
        let hint = EntitlementHintSource.shared
        hint.set(await service.cachedStatus())
        hint.set(await service.refresh())
        for await status in await service.statusUpdates() {
            hint.set(status)
        }
    }
}
