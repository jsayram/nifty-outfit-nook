import Foundation

/// Which stylist answers a Style Me request (Phase 28).
public enum StylistLane: String, CaseIterable, Hashable, Sendable, Codable {
    /// The cloud stylist (27a), as a paid job (27c). Needs the backend, her consent and a
    /// connection.
    case cloud
    /// Apple's on-device model, on an iPhone with Apple Intelligence. Not built yet: no stylist
    /// is installed for it (`NookServices.onDeviceStylist`), so this lane isn't used today.
    case onDevice
    /// Quick ideas, the rule-based stylist on the phone. Always there.
    case rules
}

/// Why the cloud stylist didn't answer, shown with quick ideas so she knows why and what to do.
public enum QuickIdeasReason: Hashable, Sendable {
    /// There's no backend in this build, so the phone is the only stylist.
    case cloudNotSetUp
    /// She hasn't agreed to send requests to the stylist's provider, or withdrew it.
    case needsConsent
    /// No connection.
    case offline
    /// A server limit: paused (24b's switch), her allowance used up, too many at once, signed out.
    case limited(CloudLimitProblem)
    /// The cloud stylist ran and didn't finish. Nothing was charged.
    case cloudDidNotFinish
}

/// Whether Apple's on-device model can run here (Foundation Models'
/// `SystemLanguageModel.default.availability`).
public enum OnDeviceModelStatus: Hashable, Sendable {
    case available
    /// The device doesn't support Apple Intelligence (iPhone 12, Lily's phone).
    case deviceNotEligible
    /// The device could, but Apple Intelligence is off.
    case appleIntelligenceNotEnabled
    /// The model is still downloading, or not ready for another system reason.
    case modelNotReady
    /// Any other reason, or Foundation Models isn't there at all.
    case unavailable
}

/// Reads the on-device model's status.
public protocol OnDeviceModelCheck: Sendable {
    func status() -> OnDeviceModelStatus
}

/// No on-device model: previews, tests, and anywhere the app doesn't set the real check.
public struct NoOnDeviceModel: OnDeviceModelCheck {
    public init() {}
    public func status() -> OnDeviceModelStatus { .unavailable }
}

/// What the router decides from.
public struct StylistConditions: Equatable, Sendable {
    /// The cloud stylist is configured (`NookServices.cloudStyling`).
    public var cloudSetUp: Bool
    /// She agreed to send styling requests to the stylist's provider.
    public var hasConsent: Bool
    public var connection: ConnectionState
    public var onDeviceModel: OnDeviceModelStatus
    /// An on-device stylist is installed (`NookServices.onDeviceStylist`).
    public var hasOnDeviceStylist: Bool

    public init(
        cloudSetUp: Bool, hasConsent: Bool, connection: ConnectionState,
        onDeviceModel: OnDeviceModelStatus = .unavailable, hasOnDeviceStylist: Bool = false
    ) {
        self.cloudSetUp = cloudSetUp
        self.hasConsent = hasConsent
        self.connection = connection
        self.onDeviceModel = onDeviceModel
        self.hasOnDeviceStylist = hasOnDeviceStylist
    }
}

/// The router's answer: which stylist, and why it isn't the cloud when it isn't.
public struct StylistRoute: Hashable, Sendable {
    public var lane: StylistLane
    /// `nil` exactly when the lane is the cloud.
    public var reason: QuickIdeasReason?

    public init(lane: StylistLane, reason: QuickIdeasReason?) {
        self.lane = lane
        self.reason = reason
    }

    public static let cloud = StylistRoute(lane: .cloud, reason: nil)
}

/// Decides which stylist answers (Phase 28). The cloud stylist when it's set up, she agreed and
/// the phone is online (an unknown connection counts as online, as in Phase 26); otherwise the
/// on-device model when it's available and a stylist is installed for it; otherwise Quick ideas.
/// Limits are only known from the server's answer, so a cloud attempt that's refused or fails
/// falls back the same way (`fallback(after:_:)`), and never costs anything.
public enum StylistRouter {
    public static func route(_ conditions: StylistConditions) -> StylistRoute {
        if !conditions.cloudSetUp { return onPhone(.cloudNotSetUp, conditions) }
        if !conditions.hasConsent { return onPhone(.needsConsent, conditions) }
        if conditions.connection == .offline { return onPhone(.offline, conditions) }
        return .cloud
    }

    /// Where to go after the cloud stylist couldn't answer: on the phone, with the reason. `nil`
    /// when there's nothing to fall back to: she cancelled, or the request itself changed.
    public static func fallback(after error: StylistError, _ conditions: StylistConditions) -> StylistRoute? {
        reason(after: error).map { onPhone($0, conditions) }
    }

    /// Why the cloud didn't answer, for an error from it. `nil` for her Cancel and a changed
    /// request, which quick ideas can't help with.
    public static func reason(after error: StylistError) -> QuickIdeasReason? {
        switch error {
        case .offline: .offline
        case .needsConsent: .needsConsent
        case .limited(.needsConsent): .needsConsent
        case .limited(.didNotFinish): .cloudDidNotFinish
        case .limited(let problem): .limited(problem)
        case .notCompleted, .timedOut: .cloudDidNotFinish
        case .cancelled, .invalidRequest: nil
        }
    }

    /// Why the cloud didn't answer, for a cloud job (27c) that ended in `failure`. `nil` when the
    /// request itself changed.
    public static func reason(after failure: AIJob.Failure) -> QuickIdeasReason? {
        switch failure {
        case .offline: .offline
        case .notCompleted: .cloudDidNotFinish
        case .needsConsent, .limited(.needsConsent): .needsConsent
        case .limited(.didNotFinish): .cloudDidNotFinish
        case .limited(let problem): .limited(problem)
        case .requestChanged: nil
        }
    }

    /// The on-device model when it can run and a stylist is installed for it, else Quick ideas.
    public static func onPhone(_ reason: QuickIdeasReason, _ conditions: StylistConditions) -> StylistRoute {
        let model = conditions.onDeviceModel == .available && conditions.hasOnDeviceStylist
        return StylistRoute(lane: model ? .onDevice : .rules, reason: reason)
    }
}
