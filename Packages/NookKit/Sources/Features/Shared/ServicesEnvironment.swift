import Models
import SwiftUI

extension EnvironmentValues {
    /// The app's services. The app target sets it once at the root; screens read it and never
    /// build services themselves. `nil` only in previews and tests that don't need data.
    @Entry public var services: NookServices?
}
