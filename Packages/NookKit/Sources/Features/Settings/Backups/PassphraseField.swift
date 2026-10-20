import DesignSystem
import SwiftUI

/// A passphrase field in the editor's style: a secure field on the soft tint, at least a full tap
/// target tall. Still images draw dots instead, since `ImageRenderer` can't draw a text field.
struct PassphraseField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    var isNew = false
    var submit: () -> Void = {}

    @Environment(\.closetIsStillImage) private var isStillImage
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 48

    var body: some View {
        field
            .padding(.horizontal, 14)
            .padding(.vertical, NookSpacing.small)
            .frame(maxWidth: .infinity, minHeight: max(minHeight, NookSpacing.minimumTapTarget), alignment: .leading)
            .background {
                NookRadius.shape(NookRadius.button)
                    .fill(Color.nook.tintStrong)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
            }
    }

    @ViewBuilder private var field: some View {
        if isStillImage {
            Text(text.isEmpty ? title : String(repeating: "•", count: text.count))
                .nookTextStyle(.body)
                .foregroundStyle(text.isEmpty ? Color.nook.textSecondary : Color.nook.textPrimary)
        } else {
            SecureField(title, text: $text)
                .textContentType(isNew ? .newPassword : .password)
                .nookTextStyle(.body)
                .onSubmit(submit)
                .accessibilityIdentifier(identifier)
        }
    }
}
