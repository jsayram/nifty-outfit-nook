import DesignSystem
import SwiftUI

/// Her first name as live text on the flat panel of the wall sign (RD-03, `.sign .name`).
///
/// The name uses the sign's text style, so it follows her text size, but it has to stay on the
/// panel: a long name wraps onto a second line and then shrinks until it fits. An empty name
/// shows a neutral word instead of a blank panel (RD-03.2). Until the profile loads the panel
/// stays empty, so the fallback never flashes up before her name.
struct NameSignText: View {
    /// The stored name, or `nil` while loading.
    let stored: String?

    var body: some View {
        Text(stored.map(SignName.shown) ?? "")
            .nookTextStyle(.nameSign)
            .foregroundStyle(.nook.signText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.3)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.default, value: stored)
    }
}
