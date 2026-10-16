#if DEBUG
    import DesignSystem
    import Models
    import SwiftUI

    /// The look bundle's page in the component catalog (`-catalog`, Phase 9). It lives in
    /// Features because bundles draw garments, which DesignSystem can't see.
    ///
    /// Debug builds only.
    public enum LookBundleCatalog {
        /// - Parameters:
        ///   - sampleGarments: the pieces with sample photos from `-fixtures demo:photos=samples`.
        ///     The page mixes two of them, a sticker and a tile, with drawn pieces.
        ///   - images: draws those photos.
        public static func page(sampleGarments: [Garment], images: (any ImageProvider)?) -> NookCatalogPage {
            NookCatalogPage(id: "lookBundles", title: "Look bundles") {
                LookBundleCatalogView(
                    photoGarments: LookBundleSamples.photoPieces(from: sampleGarments), images: images)
            }
        }
    }

    struct LookBundleCatalogView: View {
        let photoGarments: [Garment]
        @State private var loader: GarmentImageLoader?
        @State private var replay = 0
        @State private var lastTapped: String?

        init(photoGarments: [Garment], images: (any ImageProvider)?) {
            self.photoGarments = photoGarments
            _loader = State(initialValue: images.map { GarmentImageLoader(provider: $0) })
        }

        var body: some View {
            LookBundleDemo(photoGarments: photoGarments, replay: $replay, lastTapped: $lastTapped)
                .environment(\.garmentImages, loader)
        }
    }

    /// The page itself, also drawn by the snapshot tests.
    struct LookBundleDemo: View {
        let photoGarments: [Garment]
        @Binding var replay: Int
        @Binding var lastTapped: String?

        init(
            photoGarments: [Garment], replay: Binding<Int> = .constant(0), lastTapped: Binding<String?> = .constant(nil)
        ) {
            self.photoGarments = photoGarments
            _replay = replay
            _lastTapped = lastTapped
        }

        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.large) {
                caption("Large, with the piece list. Tap Replay to see the pieces settle in.")
                VStack(spacing: NookSpacing.medium) {
                    LookBundle(LookBundleSamples.byPieceCount[2], size: .large, animatesEntrance: true)
                        .id(replay)
                    Button {
                        replay += 1
                    } label: {
                        Text(verbatim: "Replay")
                    }
                    .buttonStyle(.nook(.pill, size: .small))
                    LookPieceList(content: LookBundleSamples.byPieceCount[2])
                }
                .frame(maxWidth: .infinity)

                caption("2 to 6 pieces, medium")
                NookFlowLayout(spacing: NookSpacing.medium, lineSpacing: NookSpacing.large) {
                    ForEach(LookBundleSamples.byPieceCount + [LookBundleSamples.dressLook]) { look in
                        LookBundle(look, size: .medium)
                    }
                }

                caption("Something new: one piece she doesn't own")
                VStack(spacing: NookSpacing.medium) {
                    LookBundle(LookBundleSamples.somethingNew, size: .large)
                    LookPieceList(content: LookBundleSamples.somethingNew, showsSameAsSimple: true) { piece in
                        lastTapped = "Find one: \(piece.name)"
                    }
                }
                .frame(maxWidth: .infinity)

                caption("Thumbnails you can tap")
                // Wraps at large text sizes, so a label never breaks mid-word.
                NookFlowLayout(spacing: NookSpacing.small, lineSpacing: NookSpacing.medium) {
                    ForEach(LookBundleSamples.versions, id: \.content.id) { version in
                        Button {
                            lastTapped = version.title
                        } label: {
                            VStack(spacing: NookSpacing.xSmall) {
                                LookBundle(version.content, size: .small, title: version.title)
                                Text(version.title)
                                    .nookTextStyle(.caption)
                                    .foregroundStyle(.nook.accent)
                                    .fixedSize()
                                    .accessibilityHidden(true)
                            }
                            .frame(minWidth: NookSpacing.minimumTapTarget, minHeight: NookSpacing.minimumTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let lastTapped {
                    caption("Tapped: \(lastTapped)")
                }

                if !photoGarments.isEmpty {
                    caption("Her photos: clean cutouts as stickers, the rest as tiles, beside drawn pieces")
                    LookBundle(LookBundleSamples.withPhotos(photoGarments), size: .large)
                        .frame(maxWidth: .infinity)
                }
            }
        }

        private func caption(_ text: String) -> some View {
            Text(verbatim: text)
                .nookTextStyle(.caption)
                .foregroundStyle(.nook.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
