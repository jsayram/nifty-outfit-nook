import DesignSystem
import Models
import SwiftUI
import UIKit

/// A try-on picture as the screens draw it (RD-06, RD-08).
///
/// Stage A's pictures are simulated: the look's pieces as they were when the picture was made,
/// laid out as its sticker bundle on a plain warm backdrop, with a "Simulated" badge. There is no
/// person and no body in it (the brief for Phase 12b; RD-03.4). A generated picture (Phase 33)
/// draws its image here instead, keeping the badge (RD-04.2). The fixtures' sample previews are
/// generated pictures: the photo shows whole on the backdrop, and until it has loaded, or when
/// there's no provider for it, the bundle is drawn as for any simulated picture.
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
    @Environment(\.garmentImages) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loadedPhoto: LoadedPhoto?

    static let aspectRatio: CGFloat = 4 / 5

    /// Below this width the badge is left off (a small thumbnail in a list says Simulated in its
    /// words instead).
    static let badgeMinimumWidth: CGFloat = 120

    var height: CGFloat { width / Self.aspectRatio }

    /// A photo at the size it was asked for.
    private struct LoadedPhoto {
        let reference: PhotoReference
        let pixelSize: Int
        let image: UIImage?
    }

    /// The photo is as tall as the picture, so that's the long side to load.
    private var photoPixelSize: Int { Int((height * displayScale).rounded(.up)) }

    /// The try-on photo, once it's loaded (or already cached, which still images need).
    private var photo: UIImage? {
        guard let reference = content.tryOnPhoto else { return nil }
        if let loadedPhoto, loadedPhoto.reference == reference, loadedPhoto.pixelSize == photoPixelSize {
            return loadedPhoto.image
        }
        return loader?.cachedImage(for: reference, maxPixelSize: photoPixelSize)
    }

    var body: some View {
        ZStack {
            backdrop
            if scenePhase == .active {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width, height: height)
                        .accessibilityHidden(true)
                } else {
                    LookBundle(content, size: LookBundleSize(width: width * 0.78), title: lookName)
                        .accessibilityHidden(true)
                }
                if width >= Self.badgeMinimumWidth {
                    Self.badge
                        .padding(Self.badgePadding(width: width))
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
        .task(id: TryOnPhotoRequest(reference: content.tryOnPhoto, pixelSize: photoPixelSize)) {
            guard let reference = content.tryOnPhoto, let loader else { return }
            let pixelSize = photoPixelSize
            let image = await loader.image(for: reference, maxPixelSize: pixelSize)
            if !Task.isCancelled {
                loadedPhoto = LoadedPhoto(reference: reference, pixelSize: pixelSize, image: image)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(TryOnText.spokenPicture(of: content, lookName: lookName, locale: locale)))
        .accessibilityAddTraits(.isImage)
    }

    /// The Simulated badge in the picture's corner. It's words on the picture, like the room's
    /// plates, so it stops growing at xxxLarge: at AX5 it broke as "Simu-lated" over two lines
    /// and covered the top of the picture (QA, 17 October 2026, iPhone 12). The page says the
    /// picture is simulated at full size, and VoiceOver reads it with the picture.
    static var badge: some View {
        NookBadge(SharedText.simulated, systemImage: "camera")
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    static func badgePadding(width: CGFloat) -> CGFloat {
        width >= 240 ? NookSpacing.medium : NookSpacing.small
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

/// What `TryOnPictureView` loads: the photo, at a size, and nothing for a simulated picture.
private struct TryOnPhotoRequest: Hashable {
    let reference: PhotoReference?
    let pixelSize: Int
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
        if case .generated(let photo) = picture.image { tryOnPhoto = photo }
    }
}
