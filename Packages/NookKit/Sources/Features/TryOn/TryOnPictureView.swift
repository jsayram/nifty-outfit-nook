import DesignSystem
import Models
import SwiftUI

/// A try-on picture as the screens draw it (RD-06, RD-08).
///
/// Stage A's pictures are simulated: the look's pieces as they were when the picture was made,
/// laid out as its sticker bundle on a plain warm backdrop, with a "Simulated" badge. There is no
/// person and no body in it (the brief for Phase 12b; RD-03.4). A generated picture (Phase 33)
/// will draw its image here instead, keeping the badge (RD-04.2).
///
/// A picture is Sensitive, so it's hidden while the app isn't active: the app switcher keeps a
/// snapshot of the screen, and it shouldn't hold a picture of her (SECURITY_STANDARD §4).
///
/// Portrait, 4:5, at any width. VoiceOver reads it as one image.
struct TryOnPictureView: View {
    let content: LookBundleContent
    /// The name VoiceOver gives the look in the picture.
    let lookName: String
    let width: CGFloat

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    static let aspectRatio: CGFloat = 4 / 5

    /// Below this width the badge is left off (a small thumbnail in a list says Simulated in its
    /// words instead).
    static let badgeMinimumWidth: CGFloat = 120

    var height: CGFloat { width / Self.aspectRatio }

    var body: some View {
        ZStack {
            backdrop
            if scenePhase == .active {
                LookBundle(content, size: LookBundleSize(width: width * 0.78), title: lookName)
                    .accessibilityHidden(true)
                if width >= Self.badgeMinimumWidth {
                    NookBadge(TryOnText.simulated, systemImage: "camera")
                        .padding(width >= 240 ? NookSpacing.medium : NookSpacing.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Image(systemName: "eye.slash")
                    .font(.system(size: width * 0.16))
                    .foregroundStyle(.nook.textSecondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .background {
            shape
                .fill(Color.nook.tint)
                .softShadow(.drop, in: shape)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(TryOnText.spokenPicture(of: content, lookName: lookName, locale: locale)))
        .accessibilityAddTraits(.isImage)
    }

    private var shape: some Shape {
        NookRadius.shape(width >= 240 ? NookRadius.tile : NookRadius.small)
    }

    /// A plain studio backdrop in the room's stone and sand, lighter in the middle. No floor
    /// line, no silhouette.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [.nook.artStone, .nook.artSand], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [.nook.tint, .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0,
                endRadius: width * 0.62)
        }
    }
}

extension LookBundleContent {
    /// What a try-on picture shows: the look's pieces when the picture was made. Nothing is faded,
    /// since the picture doesn't change when a piece later leaves her closet. A garment deleted
    /// for good can't be drawn and is left out.
    init(picture: TryOnPicture, garments: [Garment.ID: Garment]) {
        let look = Look(
            id: picture.lookID, pieces: picture.captured.pieces, name: picture.captured.name,
            occasion: picture.captured.occasion, createdAt: picture.createdAt)
        let drawn = LookBundleContent(look: look, garments: garments)
        self.init(
            id: picture.id.rawValue,
            name: picture.captured.name,
            layoutSeed: picture.lookID.rawValue,
            pieces: drawn.pieces.map { piece in
                LookBundlePiece(
                    id: piece.id, name: piece.name, category: piece.category, colors: piece.colors,
                    photo: piece.photo, cutout: piece.cutout, isIdea: piece.isIdea)
            })
    }
}
