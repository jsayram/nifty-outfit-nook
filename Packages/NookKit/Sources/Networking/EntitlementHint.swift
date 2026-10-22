import Foundation
import Models
import Synchronization

/// The subscription hint paid requests carry (30a): `X-Nook-Entitlement-Hint`, one of
/// `EntitlementHint`'s values. It's only a hint. The server never grants anything because of it;
/// its own check against Apple's records comes in 30c. The app keeps it current from StoreKit.
public final class EntitlementHintSource: Sendable {
    /// The one the app sets, and every `GatewayPaidActionService` reads by default.
    public static let shared = EntitlementHintSource()

    public static let header = "X-Nook-Entitlement-Hint"

    private let status = Mutex<SubscriptionStatus?>(nil)
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// The hint for the last status, worked out when a request is sent, so a free month that has
    /// ended since reads as expired. Nil (no status yet) sends no header.
    public var current: EntitlementHint? { status.withLock { $0 }?.hint(at: now()) }

    public func set(_ newValue: SubscriptionStatus?) {
        status.withLock { $0 = newValue }
    }
}

/// Adds the hint to what another signer (App Attest) adds.
struct HintedSigner: RequestSigner {
    let base: any RequestSigner
    let hint: EntitlementHint?

    func headers(for endpoint: APIV1.Endpoint, idempotencyKey: String, body: Data) async throws(APIFailure)
        -> [String: String]
    {
        var headers = try await base.headers(for: endpoint, idempotencyKey: idempotencyKey, body: body)
        if let hint { headers[EntitlementHintSource.header] = hint.rawValue }
        return headers
    }
}
