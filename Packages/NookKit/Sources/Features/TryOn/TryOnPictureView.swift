import DesignSystem
import Models
import SwiftUI
import UIKit

/// A try-on picture as the screens draw it (RD-06, RD-08).
///
/// Two kinds, both with a "Simulated" badge (RD-04.2):
/// - A picture drawn from the pieces (`TryOnImage.simulated`): the look's pieces as they were
///   when the picture was made, laid out as its sticker bundle on a plain warm backdrop, with no
///   one wearing them.
/// - A picture of a person wearing the look (`TryOnImage.generated`, Phase 33; in the fixtures,
///   the sample previews of the person in the example try-on photo). The photo is a tall phone
///   photo, so it fills the 4:5 frame at its full height, a little cropped at the top and bottom,
///   over a soft blurred copy of itself where it doesn't reach the sides: no flat bands. Its badge
///   sits in the bottom corner, on the floor, so it never covers her face, and only on a picture
///   wide enough to keep it off her feet too. Until the photo has
///   loaded, or when there's no provider for it, the bundle is drawn as for the first kind.
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
    /// Over a person the badge needs a wider picture: in a narrower one, even in the bottom
    /// corner it reached her feet. There the words beside the picture say Simulated (the grid's
    /// date line, the Try it on sheet's subtitle, look detail's picture rows).
    static let photoBadgeMinimumWidth: CGFloat = 240

    static func showsBadge(width: CGFloat, showsPerson: Bool) -> Bool {
        width >= (showsPerson ? photoBadgeMinimumWidth : badgeMinimumWidth)
    }

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
                    Self.photoFill(photo, width: width, height: height)
                        .accessibilityHidden(true)
                } else {
                    LookBundle(content, size: LookBundleSize(width: width * 0.78), title: lookName)
                        .accessibilityHidden(true)
                }
                if Self.showsBadge(width: width, showsPerson: photo != nil) {
                    Self.badge
                        .padding(Self.badgePadding(width: width))
                        .frame(
                            maxWidth: .infinity, maxHeight: .infinity,
                            alignment: Self.badgeAlignment(showsPerson: photo != nil))
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

    /// Over a drawn picture the top corner is empty space. Over a person it's her head, so the
    /// badge goes to the bottom corner, on the floor beside her feet.
    static func badgeAlignment(showsPerson: Bool) -> Alignment {
        showsPerson ? .bottomLeading : .topLeading
    }

    /// How much of a tall photo's height the frame shows: it trims a little off the top and the
    /// bottom (empty wall and floor in a full-length photo), more off the top, so the feet stay
    /// in.
    static let photoHeightShown: CGFloat = 0.94

    /// A tall photo in the 4:5 frame: at its full height, trimmed a little top and bottom, over a
    /// blurred copy that fills the sides. A photo as wide as the frame or wider just fills it.
    @ViewBuilder
    static func photoFill(_ photo: UIImage, width: CGFloat, height: CGFloat) -> some View {
        let aspect = photo.size.height > 0 ? photo.size.width / photo.size.height : aspectRatio
        let shownHeight = height / photoHeightShown
        let shownWidth = shownHeight * aspect
        if shownWidth >= width {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else {
            ZStack {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .blur(radius: width * 0.06, opaque: true)
                    .clipped()
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: shownWidth, height: shownHeight)
                    // Soft sides, so the photo melts into its blurred copy instead of ending in a line.
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
                            ], startPoint: .leading, endPoint: .trailing)
                    }
                    // A full-length photo has more room over the head than under the feet.
                    .offset(y: -(shownHeight - height) * 0.3)
            }
            .frame(width: width, height: height)
            .clipped()
        }
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
