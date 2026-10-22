import DesignSystem
import Models
import SwiftUI
import UIKit

/// 33a: "See what was sent" for one try-on picture: exactly the images that left her iPhone, as
/// the bytes that were sent (kept with the picture): the faceless photo on the studio backdrop,
/// then each garment photo. The approved line says where they went.
///
/// The faceless photo shows her body, so it's hidden while the app isn't active, like the
/// pictures (SECURITY_STANDARD §4).
struct SentImagesView: View {
    let sent: TryOnSent
    let garments: [Garment.ID: Garment]

    @Environment(\.garmentImages) private var loader
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var images: [PhotoReference: UIImage] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NookSpacing.large) {
                Text(TryOnConsentText.underPicture)
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sent.line")
                // 33c: what our server does on the way, in the words of the consent.
                Text(WalkthroughText.serverNote)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sent.serverNote")
                VStack(alignment: .leading, spacing: NookSpacing.small) {
                    Text(SentText.photoHeader)
                        .nookTextStyle(.headline)
                        .foregroundStyle(.nook.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    image(sent.person, width: 240, label: SentText.photoLabel, identifier: "sent.person")
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: NookSpacing.small) {
                    Text(SentText.garmentsHeader(sent.garments.count))
                        .nookTextStyle(.headline)
                        .foregroundStyle(.nook.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: NookSpacing.medium)],
                        spacing: NookSpacing.medium
                    ) {
                        ForEach(sent.garments, id: \.image) { garment in
                            let name = garments[garment.garmentID]?.name ?? SentText.pieceGone
                            VStack(spacing: NookSpacing.xSmall) {
                                image(garment.image, width: 120, label: name, identifier: "sent.garment")
                                Text(name)
                                    .nookTextStyle(.note)
                                    .foregroundStyle(.nook.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                Text(SentText.notSent)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(NookSpacing.medium)
        }
        .accessibilityIdentifier("sent")
        .task {
            guard let loader else { return }
            for reference in sent.imageReferences where images[reference] == nil {
                let pixelSize = Int((240 * displayScale).rounded(.up))
                if let image = await loader.image(for: reference, maxPixelSize: pixelSize) { images[reference] = image }
            }
        }
    }

    private func image(_ reference: PhotoReference, width: CGFloat, label: String, identifier: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: NookRadius.small, style: .continuous)
        return ZStack {
            shape.fill(Color.nook.tint)
            if scenePhase == .active, let image = images[reference] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if scenePhase != .active {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.nook.textSecondary)
            }
        }
        .frame(width: width, height: width * 4 / 3)
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(identifier)
    }
}

/// The words for "See what was sent".
nonisolated enum SentText {
    static var title: String {
        String(localized: "See what was sent", bundle: .module, comment: "Button and title (33a)")
    }

    static var hint: String {
        String(
            localized: "Shows the photos that left your iPhone to make this picture.", bundle: .module,
            comment: "VoiceOver hint for See what was sent")
    }

    static var photoHeader: String {
        String(
            localized: "Your photo, without your face, on a plain backdrop", bundle: .module,
            comment: "See what was sent: the faceless photo")
    }

    static var photoLabel: String {
        String(
            localized:
                "The photo that was sent: your body on a plain studio backdrop, with your head covered in flat grey.",
            bundle: .module, comment: "VoiceOver: the faceless photo on See what was sent")
    }

    static func garmentsHeader(_ count: Int) -> String {
        String(
            localized: "\(count) clothing photos", bundle: .module,
            comment: "See what was sent: the garment photos. The argument is how many. Pluralized.")
    }

    static var pieceGone: String {
        String(localized: "A piece no longer in your closet", bundle: .module, comment: "See what was sent")
    }

    static var notSent: String {
        String(
            localized: "Nothing else was sent: not your face, your room, your measurements, your notes or your name.",
            bundle: .module, comment: "See what was sent: under the photos")
    }
}
