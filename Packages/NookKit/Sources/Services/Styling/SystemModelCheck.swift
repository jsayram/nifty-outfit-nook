import FoundationModels
import Models

/// Whether Apple's on-device model can run on this iPhone (Phase 28), from Foundation Models'
/// `SystemLanguageModel.default.availability`. It needs a device that supports Apple Intelligence
/// (iPhone 15 Pro and later), with Apple Intelligence on and the model downloaded. On Lily's
/// iPhone 12 it says `deviceNotEligible`, so Style Me uses the cloud stylist or Quick ideas.
public struct SystemModelCheck: OnDeviceModelCheck {
    public init() {}

    public func status() -> OnDeviceModelStatus {
        Self.status(for: SystemLanguageModel.default.availability)
    }

    static func status(for availability: SystemLanguageModel.Availability) -> OnDeviceModelStatus {
        switch availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .unavailable
        }
    }
}
