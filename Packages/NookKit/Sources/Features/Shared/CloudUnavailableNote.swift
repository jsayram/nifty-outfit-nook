import DesignSystem
import SwiftUI

/// What a cloud feature shows in a build with no backend settings (32b, L9): a calm "not
/// available right now" and one plain sentence about what it means. Nothing is simulated and
/// nothing is sent, and there is nothing to retry: the build has no service to retry against.
struct CloudUnavailableNote: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Label {
                Text(SharedText.notAvailableNow)
            } icon: {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.nook.accent)
            }
            .nookTextStyle(.headline)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            Text(message)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cloud.unavailable")
    }
}
