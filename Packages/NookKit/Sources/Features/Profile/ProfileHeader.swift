import DesignSystem
import SwiftUI

/// The top of Profile (`settings.html`): the hallway wall with "Profile" in display type, her
/// name sign hanging in the middle, a floor plant in the corner and a strip of floor.
///
/// The sign is the same drawing as on Home at 1.3 times the size, with her name as live text on
/// its panel. Tapping it opens the same editor as the Name on your sign row. An empty name shows
/// "Hello" (RD-03.2). At the accessibility sizes the plant is left out; the sign stays, and the
/// row under it carries her name at full size (RD-03.3).
struct ProfileHeader: View {
    /// The stored name, or `nil` while loading.
    let signName: String?
    let editName: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `name-sign.svg` at 1.3 (`.sign` in `settings.html`).
    static let signSize = CGSize(width: 143, height: 83.2)
    /// The flat panel the name sits on, inside the sign.
    static let signName = CGRect(x: 22.1, y: 35.1, width: 98.8, height: 33.8)
    static let floorBand: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ProfileText.title)
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, NookSpacing.xLarge)
                .padding(.top, NookSpacing.small)
            sign
                .frame(maxWidth: .infinity)
                .padding(.top, NookSpacing.xLarge)
                .padding(.bottom, NookSpacing.xxLarge + Self.floorBand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            VStack(spacing: 0) {
                Color.nook.wallGradient
                Rectangle()
                    .fill(Color.nook.floorLine)
                    .frame(height: 2)
                Color.nook.floor
                    .frame(height: Self.floorBand)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !dynamicTypeSize.isAccessibilitySize {
                // The pot's foot rests on the floor strip, as in the mockup.
                RoomArtImage(.floorPlant)
                    .frame(width: 60, height: 103)
                    .padding(.trailing, NookSpacing.large)
                    .padding(.bottom, Self.floorBand / 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var sign: some View {
        Button(action: editName) {
            ZStack(alignment: .topLeading) {
                RoomArtImage(.nameSign)
                NameSignText(stored: signName)
                    .frame(width: Self.signName.width, height: Self.signName.height)
                    .offset(x: Self.signName.minX, y: Self.signName.minY)
            }
            .frame(width: Self.signSize.width, height: Self.signSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ProfileText.spokenSign(signName ?? "")))
        .accessibilityHint(Text(ProfileText.signHint))
        .accessibilityIdentifier("profile.sign")
    }
}
