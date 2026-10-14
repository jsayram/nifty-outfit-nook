import DesignSystem
import Models
import SwiftUI
import UIKit

/// How a garment's picture sits on a screen.
enum GarmentPresentation: Equatable {
    /// A sticker with a thick white edge and a soft shadow (RD-07): garment detail now, and
    /// every look from Phase 9. A resting sticker sits on the bottom of its space.
    case sticker(StickerSpec.Placement)
    /// Standing on the floor with no edge, as her pieces do in the Closet grid (`closet.html`).
    case standing
}

/// A garment's picture: the one place every screen gets it from, so a piece looks the same
/// everywhere (Phase 8b).
///
/// `GarmentArtChoice` picks what to show from the piece's photo and cutout: the clean cutout,
/// the photo in a rounded tile when there's no clean cutout, or the drawing of its kind when
/// there's no photo. The presentation decides how: a cutout or drawing becomes a `NookSticker`,
/// or stands plain on the floor; the photo becomes a `NookPhotoTile` either way. Every
/// choice takes exactly `size`, so a piece that falls back never moves the layout.
///
/// Photos and cutouts load through `GarmentImageLoader` at the size shown, away from the main
/// actor. A picture the provider doesn't have (every Stage A sample) falls back to the drawing.
struct GarmentPicture: View {
    let photo: PhotoReference
    let cutout: GarmentCutout?
    let category: GarmentCategory
    let colors: [ColorName]
    /// The space the picture takes, in points.
    let size: CGSize
    let presentation: GarmentPresentation

    @Environment(\.garmentImages) private var loader
    @Environment(\.displayScale) private var displayScale
    @Environment(\.closetIsStillImage) private var isStillImage
    @State private var loaded: Loaded?

    init(
        photo: PhotoReference, cutout: GarmentCutout? = nil, category: GarmentCategory, colors: [ColorName],
        size: CGSize, presentation: GarmentPresentation = .standing
    ) {
        self.photo = photo
        self.cutout = cutout
        self.category = category
        self.colors = colors
        self.size = size
        self.presentation = presentation
    }

    init(_ garment: Garment, size: CGSize, presentation: GarmentPresentation = .standing) {
        self.init(
            photo: garment.photo, cutout: garment.cutout, category: garment.category, colors: garment.colors,
            size: size, presentation: presentation)
    }

    /// A photo or cutout to load, at a size in pixels.
    private struct Request: Hashable {
        let reference: PhotoReference
        let pixelSize: Int
    }

    private struct Loaded {
        let request: Request
        let image: UIImage?
    }

    private enum PictureState {
        case loading
        case ready(UIImage)
        case missing
    }

    var body: some View {
        let choice = GarmentArtChoice(photo: photo, cutout: cutout)
        let request = request(for: choice)
        // The clear layer keeps the view in place while a sticker waits for its photo, so the
        // load below always starts.
        ZStack {
            Color.clear
            content(choice, request: request)
        }
        .frame(width: size.width, height: size.height)
        .task(id: request) {
            guard let request, let loader, loaded?.request != request else { return }
            let image = await loader.image(for: request.reference, maxPixelSize: request.pixelSize)
            if !Task.isCancelled { loaded = Loaded(request: request, image: image) }
        }
    }

    @ViewBuilder
    private func content(_ choice: GarmentArtChoice, request: Request?) -> some View {
        switch (choice, request.map(state(for:))) {
        case (.cutout(let reference), .ready(let image)?):
            cutout(image, reference: reference)
        case (.photoTile, .ready(let image)?):
            if let photo = image.cgImage {
                NookPhotoTile(
                    TileFraming.crop(photo, subject: cutout?.quality.subjectBounds, tileSize: size), size: size)
            } else {
                drawing
            }
        case (_, .loading?):
            // The plain drawing keeps the grid steady while a photo loads; a sticker waits.
            if presentation == .standing { drawing }
        default:
            drawing
        }
    }

    /// The cutout, with the sticker edge or standing plain.
    @ViewBuilder
    private func cutout(_ image: UIImage, reference: PhotoReference) -> some View {
        switch presentation {
        case .sticker(let placement):
            if let picture = image.cgImage {
                NookSticker(
                    "cutout:\(String(describing: reference))", size: size, source: .image(picture), placement: placement
                )
            }
        case .standing:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
    }

    /// The drawing of its kind in its colours, as a sticker or standing plain.
    @ViewBuilder private var drawing: some View {
        switch presentation {
        case .sticker(let placement):
            let sticker = Self.drawingSticker(category: category, colors: colors)
            NookSticker(sticker.id, size: size, source: sticker.source, placement: placement)
        case .standing:
            GarmentPlaceholderArt(category: category, colors: colors)
        }
    }

    /// The sticker of a kind's drawing in its colours: its cache name and how it's drawn.
    nonisolated static func drawingSticker(category: GarmentCategory, colors: [ColorName]) -> (
        id: String, source: StickerSource
    ) {
        (
            GarmentDrawing.stickerID(category: category, colors: colors),
            .drawn { spec in GarmentDrawing.image(category: category, colors: colors, for: spec) }
        )
    }

    /// What to load for `choice`: the cutout at the size shown, or the photo half as big again,
    /// so a tile cropped in to the garment stays sharp.
    private func request(for choice: GarmentArtChoice) -> Request? {
        Self.pictureToLoad(for: choice, size: size, scale: displayScale).map {
            Request(reference: $0.reference, pixelSize: $0.pixelSize)
        }
    }

    /// The photo or cutout a choice needs, and its size in pixels.
    nonisolated static func pictureToLoad(for choice: GarmentArtChoice, size: CGSize, scale: CGFloat) -> (
        reference: PhotoReference, pixelSize: Int
    )? {
        let longSide = max(size.width, size.height) * scale
        switch choice {
        case .drawing: return nil
        case .cutout(let reference): return (reference, Int(longSide.rounded(.up)))
        case .photoTile(let reference, _): return (reference, Int((longSide * 1.5).rounded(.up)))
        }
    }

    private func state(for request: Request) -> PictureState {
        if let loaded, loaded.request == request {
            return loaded.image.map(PictureState.ready) ?? .missing
        }
        guard let loader else { return .missing }
        if let image = loader.cachedImage(for: request.reference, maxPixelSize: request.pixelSize) {
            return .ready(image)
        }
        if loader.isMissing(request.reference, maxPixelSize: request.pixelSize) { return .missing }
        // A still image can't wait for a load.
        return isStillImage ? .missing : .loading
    }
}
