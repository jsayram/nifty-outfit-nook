import Foundation
import Models
import Networking
import Services

/// Which stylist Style Me uses (Phase 27a). The cloud stylist, through the backend's
/// POST /v1/style, once the real services are configured (`docs/backend-switch.md`); Stage A's
/// stylist on the phone until then, which sends nothing. Debug builds can try the cloud stylist
/// against the in-process fake backend with `-cloud-stylist` (and `-cloud-stylist fails` for a
/// provider that fails). The app never names a provider or a model either way.
nonisolated enum AppStylist {
    /// - Parameters:
    ///   - paid: the gateway's paid actions (`AppGateway.paid`), when the cloud stylist is on.
    ///   - keepsSettings: whether her consent is kept on the iPhone. The debug sample closet that
    ///     UI tests open keeps nothing.
    static func install(
        into services: inout NookServices, paid: (any PaidActionService)?, keepsSettings: Bool = true
    ) {
        guard let paid else { return }
        let consent: any StylistConsentStore =
            keepsSettings ? DefaultsStylistConsentStore() : InMemoryStylistConsentStore()
        services.stylistConsent = consent
        services.stylist = CloudStylist(paid: paid, consent: consent)
        services.cloudStyling = true
    }

    @MainActor
    static func usesCloud(_ arguments: [String]) -> Bool {
        if AppGateway.settings.usesRealServices { return true }
        #if DEBUG
            return arguments.contains("-cloud-stylist")
        #else
            return false
        #endif
    }

    #if DEBUG
        /// `-cloud-stylist [normal|fails|slow]` against the fake backend: signs in with the fake Apple
        /// sign-in at launch (paid requests need an account) and sets how its stylist behaves.
        @MainActor
        static func prepareFakeIfAsked(arguments: [String]) async {
            guard let index = arguments.firstIndex(of: "-cloud-stylist"), let fake = AppGateway.fake else { return }
            let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
            fake.backend.setStylist(FakeStylistBehaviour(rawValue: value) ?? .normal)
            if !(await fake.account.isSignedIn()) { _ = try? await fake.account.signIn() }
        }
    #endif
}
