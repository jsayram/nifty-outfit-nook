import DesignSystem
import SwiftUI

/// The room as a banner at the accessibility text sizes (`.banner` in `home-ax.html`): a close-up
/// against the wall with the wardrobe's edge on the left (it opens Closet), her name sign in the
/// middle (it opens Profile) and the window on the right, following the weather.
///
/// The drawings keep the mockup's sizes, so the banner is the same height at every text size;
/// the name on the sign shrinks to fit its panel. The mockup's weather plate isn't here: the
/// weather lives on Style Me (LR-04), and the window still tells VoiceOver what it shows.
struct HomeBanner: View {
    let content: HomeRoomContent
    let open: (RoomControl) -> Void

    static let height: CGFloat = 186

    // Sizes and places from `home-ax.html`, in points.
    /// The wardrobe's visible edge, and where the whole drawing sits behind it.
    static let wardrobeEdge = CGSize(width: 72, height: height)
    static let wardrobe = CGRect(x: -94, y: -46, width: 164, height: 394)
    static let window = CGSize(width: 96, height: 184)
    static let windowInset: CGFloat = 8
    static let windowTop: CGFloat = 5
    /// `name-sign.svg` at 1.3, and the panel the name sits on.
    static let sign = CGSize(width: 143, height: 83.2)
    static let signTop: CGFloat = 40
    static let signName = CGRect(x: 22.1, y: 35.1, width: 98.8, height: 33.8)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let windowX = width - Self.windowInset - Self.window.width
            // The sign hangs in the middle of the wall between the wardrobe and the window.
            let signX = (Self.wardrobeEdge.width + windowX - Self.sign.width) / 2
            ZStack(alignment: .topLeading) {
                wardrobe
                window
                    .frame(width: Self.window.width, height: Self.window.height)
                    .offset(x: windowX, y: Self.windowTop)
                sign
                    .offset(x: signX, y: Self.signTop)
            }
        }
        .frame(height: Self.height)
        .background(Color.nook.wallGradient)
        .clipShape(NookRadius.shape(30))
        .accessibilityElement(children: .contain)
    }

    /// The right-hand edge of the wardrobe with two pieces on its rail.
    private var wardrobe: some View {
        Button {
            open(.wardrobe)
        } label: {
            ZStack(alignment: .topLeading) {
                RoomArtImage(.wardrobe)
                    .roomFrame(Self.wardrobe)
                RoomArtImage(.wardrobeRail)
                    .roomFrame(Self.rail)
            }
            .frame(width: Self.wardrobeEdge.width, height: Self.wardrobeEdge.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(BannerButtonStyle())
        .accessibilityLabel(RoomControl.wardrobe.accessibilityLabel(for: content))
        .accessibilityHint(RoomControl.wardrobe.accessibilityHint(for: content))
        .accessibilityIdentifier(RoomControl.wardrobe.identifier)
        .homeTourAnchor(.wardrobe, content: content, open: open)
    }

    /// The rail sits where it does on the room's wardrobe, scaled to this wardrobe's size.
    static var rail: CGRect {
        let scale = wardrobe.width / RoomStage.wardrobe.width
        let rail = RoomStage.wardrobeRail
        return CGRect(
            x: wardrobe.minX + (rail.minX - RoomStage.wardrobe.minX) * scale,
            y: wardrobe.minY + (rail.minY - RoomStage.wardrobe.minY) * scale,
            width: rail.width * scale,
            height: rail.height * scale)
    }

    private var window: some View {
        let window = content.window
        return ZStack {
            RoomArtImage(window.art)
                .id(window)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.4), value: window)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.accessibilityLabel ?? "")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("home.window")
        .accessibilityHidden(window.accessibilityLabel == nil)
    }

    private var sign: some View {
        Button {
            open(.nameSign)
        } label: {
            ZStack(alignment: .topLeading) {
                RoomArtImage(.nameSign)
                NameSignText(stored: content.signName)
                    .roomFrame(Self.signName)
            }
            .frame(width: Self.sign.width, height: Self.sign.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(BannerButtonStyle())
        .accessibilityLabel(RoomControl.nameSign.accessibilityLabel(for: content))
        .accessibilityHint(RoomControl.nameSign.accessibilityHint(for: content))
        .accessibilityIdentifier(RoomControl.nameSign.identifier)
        .homeTourAnchor(.nameSign, content: content, open: open)
    }
}

/// A soft dim over the drawing while it's pressed.
private struct BannerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    NookRadius.shape(NookRadius.plateSlim)
                        .fill(Color.nook.textPrimary.opacity(0.08))
                }
            }
    }
}
