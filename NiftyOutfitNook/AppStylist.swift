import Foundation
import Models
import Networking
import Services

/// Which stylist Style Me uses (Phase 27a). The cloud stylist, through the backend's
/// POST /v1/style, once the real services are configured (`docs/backend-switch.md`); Stage A's
/// stylist on the phone until then, which sends nothing. With the cloud stylist, `StylistRouter`
/// (Phase 28) still answers with Quick ideas on the phone when it can't be used. Debug builds can try the cloud stylist
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
        // Phase 28: whether Apple's on-device model can run here (never on an iPhone 12). No
        // stylist uses it yet, so the router answers from the cloud or with Quick ideas.
        services.onDeviceModel = SystemModelCheck()
        guard let paid else { return }
        let consent: any StylistConsentStore =
            keepsSettings ? DefaultsStylistConsentStore() : InMemoryStylistConsentStore()
        services.stylistConsent = consent
        services.stylist = CloudStylist(paid: paid, consent: consent)
        services.cloudStyling = true
    }

    @MainActor
    static func usesCloud(_ arguments: [String]) -> Bool {
        if AppGateway.mode == .real { return true }
        #if DEBUG
            return arguments.contains("-cloud-stylist")
        #else
            return false
        #endif
    }

    #if DEBUG
        /// `-cloud-stylist [normal|fails|slow]` against the fake backend: signs in with the fake Apple
        /// sign-in at launch (paid requests need an account) and sets how its stylist behaves.
        /// With `-signed-out` it stays signed out, so Style Me's sign-in sheet shows (Release).
        @MainActor
        static func prepareFakeIfAsked(arguments: [String]) async {
            guard let index = arguments.firstIndex(of: "-cloud-stylist"), let fake = AppGateway.fake else { return }
            let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
            fake.backend.setStylist(FakeStylistBehaviour(rawValue: value) ?? .normal)
            guard !arguments.contains("-signed-out") else { return }
            if !(await fake.account.isSignedIn()) { _ = try? await fake.account.signIn() }
        }
    #endif
}
