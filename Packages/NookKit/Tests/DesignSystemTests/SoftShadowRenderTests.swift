import SwiftUI
import Testing

@testable import DesignSystem

@MainActor
struct SoftShadowRenderTests {
    /// The chip from the README, so the documented usage keeps compiling.
    private func chip(largeShadow: Bool) -> some View {
        Text("Work")
            .nookTextStyle(.chip)
            .foregroundStyle(.nook.onAccent)
            .padding(.horizontal, NookSpacing.medium)
            .frame(minHeight: NookSpacing.minimumTapTarget)
            .background(.nook.accent, in: Capsule())
            .softShadow(largeShadow ? .dropLarge : .drop, in: Capsule())
    }

    /// The shadow is drawn behind the view and never changes its size or layout.
    @Test func shadowDoesNotChangeLayout() throws {
        let plain = ImageRenderer(
            content: Text("Work").nookTextStyle(.chip).padding(.horizontal, NookSpacing.medium)
                .frame(minHeight: NookSpacing.minimumTapTarget)
        )
        let shadowed = ImageRenderer(content: chip(largeShadow: false))
        let plainImage = try #require(plain.uiImage)
        let shadowedImage = try #require(shadowed.uiImage)
        #expect(shadowedImage.size == plainImage.size)
        #expect(ImageRenderer(content: chip(largeShadow: true)).uiImage?.size == plainImage.size)
    }
}
