import NookTestSupport
import Testing

extension Trait where Self == ConditionTrait {
    /// Skips the iPad snapshot tests unless `NOOK_IPAD_SNAPSHOTS=1` (see `IPadSnapshots`).
    static var ipadSnapshots: Self {
        .enabled(if: IPadSnapshots.isOn, "iPad testing is paused. Set NOOK_IPAD_SNAPSHOTS=1 to run it.")
    }
}
